import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import 'package:flutter_client/logic/models/dictation_profile_spec.dart';
import 'package:flutter_client/logic/models/transcription_source.dart';
import 'package:flutter_client/logic/processors/text_sanitizer.dart';
import 'package:flutter_client/logic/processors/transform_output_guard.dart';
import 'package:flutter_client/services/utility/settings_service.dart';

import 'chat_engine.dart';
import 'cloud_error.dart';

/// Rewrites a transcript in the active output style with the active cloud
/// source's LLM.
class TransformService {
  TransformService(this._settings, List<ChatEngine> engines)
    : _engines = {for (final engine in engines) engine.source: engine};

  static const int _tokenMultiplier = 2;
  static const Set<CloudErrorType> _modelGone = {
    CloudErrorType.modelRetired,
    CloudErrorType.modelUnavailable,
  };
  static final RegExp _whitespace = RegExp(r'\s+');

  final SettingsService _settings;
  final Map<TranscriptionSource, ChatEngine> _engines;

  /// When each service's last 429 said it may be asked again.
  final Map<TranscriptionSource, DateTime> _cooldownUntil = {};

  /// Returns [text] rewritten as [profile] asks, sanitized; [text] itself
  /// for a style that needs no LLM. Throws `CloudError` when the rewrite
  /// fails or its output is rejected.
  Future<String> transform(String text, DictationProfileSpec profile) async {
    if (!profile.requiresLlm) return text;

    final source = _settings.transcriptionSource;
    final engine = _engines[source];
    final service = source.label;
    final systemPrompt = profile.systemPrompt;
    if (engine == null || systemPrompt == null || systemPrompt.trim().isEmpty) {
      throw CloudError(
        service: service,
        type: CloudErrorType.badRequest,
        message: 'This style can’t run here',
      );
    }

    final until = _cooldownUntil[source];
    final now = DateTime.now().toUtc();
    if (until != null && now.isBefore(until)) {
      throw CloudError(
        service: service,
        type: CloudErrorType.rateLimited,
        message: '$service rate limit cooldown active',
        retryAfter: until.difference(now),
      );
    }

    try {
      final result = await engine.complete(
        systemPrompt: systemPrompt,
        userContent: '<transcript>\n$text\n</transcript>',
        maxTokens: _maxTokens(text),
        timeout: _timeout(text),
      );
      if (result.finishReason == 'length') {
        throw CloudError(
          service: service,
          type: CloudErrorType.unknown,
          message: 'Transform output truncated by token cap',
        );
      }
      final guarded = TransformOutputGuard.normalize(result.text, input: text);
      if (guarded == null) {
        throw CloudError(
          service: service,
          type: CloudErrorType.unknown,
          message: 'Transform output rejected by guard',
        );
      }

      return TextSanitizer.sanitize(guarded);
    } on CloudError catch (e, st) {
      final retryAfter = e.retryAfter;
      if (e.type == CloudErrorType.rateLimited && retryAfter != null) {
        _cooldownUntil[source] = DateTime.now().toUtc().add(retryAfter);
      }
      // A missing default rewrite model is the service's problem. A model
      // the user chose in Account is theirs to change, and the error says so.
      final chosenByUser =
          source == TranscriptionSource.openRouter &&
          _settings.hasCustomRewriteModel;
      if (_modelGone.contains(e.type) && !chosenByUser) {
        Error.throwWithStackTrace(
          CloudError(
            service: service,
            type: CloudErrorType.serverError,
            message: e.message,
          ),
          st,
        );
      }
      rethrow;
    }
  }

  /// Scales with the input so long dictations are not cut to raw.
  static Duration _timeout(String text) {
    final words = text.trim().split(_whitespace).where((w) => w.isNotEmpty);
    const base = AppConstants.transformTimeoutBase;
    final ms =
        (base.inMilliseconds +
                AppConstants.transformTimeoutPerWord.inMilliseconds *
                    words.length)
            .clamp(
              base.inMilliseconds,
              AppConstants.transformTimeoutMax.inMilliseconds,
            );

    return Duration(milliseconds: ms);
  }

  /// Room for a rewrite up to twice the input's estimated length.
  static int _maxTokens(String text) {
    final estimated = (text.length / AppConstants.transformCharsPerToken)
        .ceil();

    return (estimated * _tokenMultiplier).clamp(
      AppConstants.transformMinCompletionTokens,
      AppConstants.transformMaxCompletionTokens,
    );
  }
}
