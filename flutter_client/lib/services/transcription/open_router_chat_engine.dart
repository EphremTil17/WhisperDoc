import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import 'package:flutter_client/logic/models/transcription_source.dart';
import 'package:flutter_client/services/utility/settings_service.dart';

import 'chat_engine.dart';
import 'cloud_error.dart';
import 'cloud_http.dart';
import 'open_router_speech_engine.dart';

/// OpenRouter chat completions for the output styles: the rewrite model
/// (the same as on Groq unless the user chose another), on a host that is
/// quick to answer and quick to write, under the user's retention choice.
class OpenRouterChatEngine implements ChatEngine {
  OpenRouterChatEngine(this._settings, this._http);

  static final String _service = TranscriptionSource.openRouter.label;
  static final Uri _endpoint = Uri.parse(AppConstants.openRouterChatEndpoint);
  static const String _reasoningRequired = 'Reasoning is mandatory';

  final SettingsService _settings;
  final CloudHttp _http;

  @override
  TranscriptionSource get source => TranscriptionSource.openRouter;

  @override
  Future<ChatResult> complete({
    required String systemPrompt,
    required String userContent,
    required int maxTokens,
    required Duration timeout,
  }) async => ChatResult.fromCompletion(
    await _send(
      _settings.openRouterRewriteModel,
      systemPrompt: systemPrompt,
      userContent: userContent,
      maxTokens: maxTokens,
      timeout: timeout,
    ),
  );

  /// Sends [model] a one-word rewrite on the same terms as a real one, so a
  /// model that can't serve the styles is turned away before it is saved.
  /// Returns why not, as the user should read it; null when it can.
  Future<String?> checkModel(String model) async {
    try {
      final result = ChatResult.fromCompletion(
        await _send(
          model,
          systemPrompt: 'Repeat the transcript.',
          userContent: '<transcript>\nok\n</transcript>',
          maxTokens: AppConstants.openRouterRewriteCheckTokens,
          timeout: AppConstants.openRouterCatalogTimeout,
        ),
      );

      return result.text.trim().isEmpty
          ? 'This model answered with no text, so it can’t rewrite.'
          : null;
    } on CloudError catch (e) {
      return switch (e.type) {
        CloudErrorType.modelRetired => 'OpenRouter has no model by this id.',
        CloudErrorType.modelUnavailable =>
          _settings.openRouterZdr
              ? 'No host of this model keeps zero data.'
              : 'No host serves this model right now.',
        CloudErrorType.badRequest when e.message.contains(_reasoningRequired) =>
          'This model always reasons first, which is too slow for styles.',
        _ => e.userMessage,
      };
    }
  }

  Future<Map<String, dynamic>> _send(
    String model, {
    required String systemPrompt,
    required String userContent,
    required int maxTokens,
    required Duration timeout,
  }) {
    final apiKey = _settings.cachedOpenRouterApiKey;
    if (apiKey == null || apiKey.isEmpty) {
      throw CloudError(
        service: _service,
        type: CloudErrorType.invalidApiKey,
        message: 'No OpenRouter API key configured',
      );
    }

    return _http.postJson(
      _service,
      _endpoint,
      apiKey: apiKey,
      timeout: timeout,
      body: {
        'model': model,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userContent},
        ],
        'temperature': AppConstants.transformTemperature,
        'max_tokens': maxTokens,
        'stream': false,
        // No reasoning tokens: only the rewrite is wanted, and fast.
        'reasoning': {'enabled': false},
        'provider': {
          ...OpenRouterSpeechEngine.providerPreferences(
            zdr: _settings.openRouterZdr,
          ),
          // A rewrite is ~75 tokens, so both the wait for the first one and
          // the speed after it count: the quickest of the hosts that write
          // fast enough, ranked on OpenRouter's last few minutes.
          'sort': 'latency',
          'preferred_min_throughput': {
            'p50': AppConstants.openRouterRewriteMinThroughput,
          },
        },
      },
    );
  }
}
