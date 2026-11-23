import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import 'package:flutter_client/logic/models/transcription_source.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'cloud_error.dart';
import 'cloud_http.dart';
import 'groq_rate_limiter.dart';
import 'speech_engine.dart';

/// Groq's Whisper API: the WAV goes up as multipart, the OpenAI shape.
class GroqSpeechEngine implements SpeechEngine {
  GroqSpeechEngine(this._settings, this._http, {GroqRateLimiter? rateLimiter})
    : _limiter = rateLimiter ?? GroqRateLimiter();

  static final String _service = TranscriptionSource.groq.label;
  static final Uri _origin = Uri.parse(AppConstants.groqOrigin);
  static final Uri _endpoint = Uri.parse(
    AppConstants.groqTranscriptionEndpoint,
  );

  final SettingsService _settings;
  final CloudHttp _http;
  final GroqRateLimiter _limiter;

  @override
  TranscriptionSource get source => TranscriptionSource.groq;

  @override
  String? get setupProblem => (_settings.cachedGroqApiKey?.isEmpty ?? true)
      ? 'Add your Groq API key in Account.'
      : null;

  @override
  int get maxClipBytes => AppConstants.groqMaxBufferBytes;

  @override
  void warmUp() => _http.warmUp(_origin);

  @override
  Future<String> transcribe(Uint8List wav) async {
    final apiKey = _settings.cachedGroqApiKey;
    if (apiKey == null || apiKey.isEmpty) {
      throw CloudError(
        service: _service,
        type: CloudErrorType.invalidApiKey,
        message: 'No Groq API key configured',
      );
    }
    final language = _settings.groqLanguage;
    if (!AppConstants.isValidGroqLanguage(language)) {
      throw CloudError(
        service: _service,
        type: CloudErrorType.badRequest,
        message: 'Unsupported language code: "$language"',
      );
    }
    if (!_limiter.canRequest()) {
      throw CloudError(
        service: _service,
        type: CloudErrorType.rateLimited,
        message: 'Local rate limit reached',
        retryAfter: _limiter.retryAfter,
      );
    }

    // Counted before sending: success or failure, the attempt used a slot.
    _limiter.recordRequest();
    final prompt = _settings.groqPrompt;
    try {
      final response = await _http.sendRequest(
        _service,
        () => http.MultipartRequest('POST', _endpoint)
          ..headers['Authorization'] = 'Bearer $apiKey'
          ..files.add(
            http.MultipartFile.fromBytes(
              'file',
              wav,
              filename: 'audio.wav',
              contentType: MediaType('audio', 'wav'),
            ),
          )
          ..fields.addAll({
            'model': _settings.groqModel,
            'response_format': 'json',
            'temperature': '0',
            if (language.isNotEmpty) 'language': language,
            if (prompt.isNotEmpty) 'prompt': prompt,
          }),
        timeout: AppConstants.groqHttpTimeout,
      );

      return _text(response.body);
    } on CloudError catch (e) {
      // Honour the server's cool-down on the next recording too.
      final cooldown = e.retryAfter;
      if (cooldown != null) _limiter.backOff(cooldown);
      rethrow;
    }
  }

  /// `{"text": "...", "x_groq": {...}}`
  String _text(String body) {
    try {
      final json = jsonDecode(body);
      final text = json is Map<String, dynamic> ? json['text'] : null;
      if (text is String) return text;
    } on FormatException {
      // Reported below.
    }

    throw CloudError(
      service: _service,
      type: CloudErrorType.unknown,
      message: 'Groq returned no text',
    );
  }
}
