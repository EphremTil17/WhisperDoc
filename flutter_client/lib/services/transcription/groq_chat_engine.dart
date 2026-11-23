import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import 'package:flutter_client/logic/models/transcription_source.dart';
import 'package:flutter_client/services/utility/settings_service.dart';

import 'chat_engine.dart';
import 'cloud_error.dart';
import 'cloud_http.dart';

/// Groq's OpenAI-compatible chat completions, for the output styles.
class GroqChatEngine implements ChatEngine {
  GroqChatEngine(this._settings, this._http);

  static final String _service = TranscriptionSource.groq.label;
  static final Uri _endpoint = Uri.parse(
    AppConstants.groqChatCompletionsEndpoint,
  );

  final SettingsService _settings;
  final CloudHttp _http;

  @override
  TranscriptionSource get source => TranscriptionSource.groq;

  @override
  Future<ChatResult> complete({
    required String systemPrompt,
    required String userContent,
    required int maxTokens,
    required Duration timeout,
  }) async {
    final apiKey = _settings.cachedGroqApiKey;
    if (apiKey == null || apiKey.isEmpty) {
      throw CloudError(
        service: _service,
        type: CloudErrorType.invalidApiKey,
        message: 'No Groq API key configured',
      );
    }

    final json = await _http.postJson(
      _service,
      _endpoint,
      apiKey: apiKey,
      timeout: timeout,
      body: {
        'model': AppConstants.groqTransformModel,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userContent},
        ],
        'temperature': AppConstants.transformTemperature,
        'max_completion_tokens': maxTokens,
        'stream': false,
        // No reasoning tokens: only the rewrite is wanted, and fast.
        'include_reasoning': false,
      },
    );

    return ChatResult.fromCompletion(json);
  }
}
