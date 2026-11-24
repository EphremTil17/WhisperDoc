import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import 'package:flutter_client/logic/models/model_selection_problem.dart';
import 'package:flutter_client/logic/models/transcription_source.dart';
import 'package:flutter_client/services/utility/logging_service.dart';
import 'package:flutter_client/services/utility/settings_service.dart';

import 'cloud_error.dart';
import 'cloud_http.dart';
import 'open_router_catalog.dart';
import 'speech_engine.dart';

/// OpenRouter's transcription endpoint: the model the user chose, on any of
/// its hosts OpenRouter picks, never retaining audio unless they
/// turned zero data retention off.
class OpenRouterSpeechEngine implements SpeechEngine {
  OpenRouterSpeechEngine(this._settings, this._http, this._catalog);

  /// Above this, base64 and JSON encoding (tens of ms for minutes of audio)
  /// run off the UI thread so the "transcribing" animation never stutters.
  static const int _offThreadBytes = 1024 * 1024;

  static final String _service = TranscriptionSource.openRouter.label;
  static final Uri _origin = Uri.parse(AppConstants.openRouterOrigin);
  static final Uri _endpoint = Uri.parse(
    AppConstants.openRouterTranscriptionEndpoint,
  );

  final SettingsService _settings;
  final CloudHttp _http;
  final OpenRouterCatalog _catalog;

  @override
  TranscriptionSource get source => TranscriptionSource.openRouter;

  /// The model must be chosen, and usable as far as the last list shows:
  /// recording with one known to fail would throw the clip away.
  @override
  String? get setupProblem {
    if (_settings.cachedOpenRouterApiKey?.isEmpty ?? true) {
      return 'Add your OpenRouter API key in Account.';
    }

    return switch (_catalog.selectionProblem) {
      ModelSelectionProblem.none => null,
      ModelSelectionProblem.notChosen =>
        'Choose an OpenRouter model in Account.',
      ModelSelectionProblem.retired =>
        'OpenRouter stopped serving your model. Choose another in Account.',
      ModelSelectionProblem.retainsData =>
        'Zero data retention is on, and your model keeps data. '
            'Choose another in Account.',
    };
  }

  @override
  int get maxClipBytes => AppConstants.openRouterMaxBufferBytes;

  @override
  void warmUp() => _http.warmUp(_origin);

  @override
  Future<String> transcribe(Uint8List wav) async {
    final apiKey = _settings.cachedOpenRouterApiKey;
    if (apiKey == null || apiKey.isEmpty) {
      throw CloudError(
        service: _service,
        type: CloudErrorType.invalidApiKey,
        message: 'No OpenRouter API key configured',
      );
    }
    final model = _settings.openRouterModel;
    if (model == null) {
      throw CloudError(
        service: _service,
        type: CloudErrorType.modelUnavailable,
        message: 'No OpenRouter model chosen',
      );
    }

    final fields = {
      'model': model,
      'temperature': 0,
      if (_settings.openRouterLanguage.isNotEmpty)
        'language': _settings.openRouterLanguage,
      'provider': providerPreferences(zdr: _settings.openRouterZdr),
    };
    final encoded = wav.length > _offThreadBytes
        ? await Isolate.run(() => encodeRequest(fields, wav))
        : encodeRequest(fields, wav);
    final Map<String, dynamic> json;
    try {
      json = await _http.postEncodedJson(
        _service,
        _endpoint,
        apiKey: apiKey,
        encoded: encoded,
        timeout: AppConstants.openRouterHttpTimeout,
      );
    } on CloudError catch (e) {
      // Retired, or no host keeps zero data any more: a fresh list lets
      // the Account panel and home screen say so.
      if (e.type == CloudErrorType.modelRetired ||
          e.type == CloudErrorType.modelUnavailable) {
        unawaited(_catalog.refresh(force: true));
      }
      rethrow;
    }

    final usage = json['usage'];
    if (usage is Map<String, dynamic>) {
      LoggingService().debug(
        'OpenRouter: ${usage['seconds']}s audio, '
        '\$${usage['cost']}',
      );
    }
    final text = json['text'];
    if (text is String) return text;

    throw CloudError(
      service: _service,
      type: CloudErrorType.unknown,
      message: 'OpenRouter returned no text',
    );
  }

  /// OpenRouter's `provider` routing object: only hosts that keep zero
  /// data while that is on. Shared with the chat engine.
  static Map<String, Object> providerPreferences({required bool zdr}) => {
    if (zdr) 'zdr': true,
  };

  /// The request body as UTF-8 bytes: [fields] plus the clip as base64 (raw
  /// bytes, not a data URI). Every step that grows with the clip happens
  /// here, so off the UI thread it is all off.
  @visibleForTesting
  static Uint8List encodeRequest(Map<String, Object> fields, Uint8List wav) =>
      utf8.encode(
        jsonEncode({
          ...fields,
          'input_audio': {'format': 'wav', 'data': base64Encode(wav)},
        }),
      );
}
