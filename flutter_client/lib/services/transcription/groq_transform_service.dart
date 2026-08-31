import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import 'package:flutter_client/logic/models/dictation_profile_spec.dart';
import 'package:flutter_client/logic/processors/text_sanitizer.dart';
import 'package:flutter_client/logic/processors/transform_output_guard.dart';
import 'package:flutter_client/services/utility/settings_service.dart';

import 'groq_chat_client.dart';
import 'groq_error.dart';

/// Domain orchestrator for post-processing transcription text using Groq LLMs.
class GroqTransformService {
  final SettingsService _settings;
  final GroqChatClient _chatClient;
  DateTime? _cooldownUntil;

  GroqTransformService(this._settings, {GroqChatClient? chatClient})
    : _chatClient = chatClient ?? GroqChatClient();

  static const int _tokenMultiplier = 2;

  /// Transforms [text] according to [profile].
  ///
  /// Returns the sanitized rewritten text.
  /// Throws [GroqError] if transforming fails or output is rejected.
  Future<String> transform(String text, DictationProfileSpec profile) async {
    if (!profile.requiresLlm) {
      return text;
    }

    final systemPrompt = profile.systemPrompt;
    if (systemPrompt == null || systemPrompt.trim().isEmpty) {
      throw const GroqError(
        type: GroqErrorType.badRequest,
        message: 'Profile has no system prompt',
      );
    }

    // Check active 429 cooldown
    final until = _cooldownUntil;
    final now = DateTime.now().toUtc();
    if (until != null && now.isBefore(until)) {
      final remaining = until.difference(now);
      throw GroqError(
        type: GroqErrorType.rateLimited,
        message: 'Groq rate limit cooldown active',
        retryAfter: remaining.isNegative ? Duration.zero : remaining,
      );
    }

    final apiKey = await _settings.getGroqApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw const GroqError(
        type: GroqErrorType.invalidApiKey,
        message: 'No Groq API key configured',
      );
    }

    // Input-scaled timeout
    final words = text
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .length;
    final timeoutMs =
        (AppConstants.groqTransformTimeoutBase.inMilliseconds +
                (AppConstants.groqTransformTimeoutPerWord.inMilliseconds *
                    words))
            .clamp(
              AppConstants.groqTransformTimeoutBase.inMilliseconds,
              AppConstants.groqTransformTimeoutMax.inMilliseconds,
            );
    final timeout = Duration(milliseconds: timeoutMs);

    // Input-scaled token limit
    final estimatedTokens =
        (text.length / AppConstants.groqTransformCharsPerToken).ceil();
    final maxTokens = (estimatedTokens * _tokenMultiplier).clamp(
      AppConstants.groqTransformMinCompletionTokens,
      AppConstants.groqTransformMaxCompletionTokens,
    );

    try {
      final result = await _chatClient.complete(
        apiKey: apiKey,
        systemPrompt: systemPrompt,
        userContent: text,
        maxCompletionTokens: maxTokens,
        timeout: timeout,
      );

      if (result.finishReason == 'length') {
        throw const GroqError(
          type: GroqErrorType.unknown,
          message: 'Transform output truncated by token cap',
        );
      }

      final guarded = TransformOutputGuard.normalize(result.text, input: text);

      if (guarded == null) {
        throw const GroqError(
          type: GroqErrorType.unknown,
          message: 'Transform output rejected by guard',
        );
      }

      return TextSanitizer.sanitize(guarded);
    } on GroqError catch (e) {
      final retryAfter = e.retryAfter;
      if (e.type == GroqErrorType.rateLimited && retryAfter != null) {
        _cooldownUntil = DateTime.now().toUtc().add(retryAfter);
      }
      rethrow;
    }
  }

  void dispose() => _chatClient.dispose();
}
