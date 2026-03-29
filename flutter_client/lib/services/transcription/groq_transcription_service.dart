import 'package:flutter/foundation.dart';
import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import 'package:flutter_client/logic/processors/text_sanitizer.dart';
import 'package:flutter_client/services/utility/logging_service.dart';
import 'package:flutter_client/services/utility/settings_service.dart';

import 'groq_error.dart';
import 'groq_http_client.dart';
import 'groq_rate_limiter.dart';
import 'wav_encoder.dart';

/// Domain-level orchestrator for Groq Cloud speech-to-text.
///
/// Manages a local audio buffer, delegates WAV encoding, enforces rate limits,
/// and exposes a clean API that [RecordingController] consumes. Sits parallel
/// to [WebSocketService] — never touches the WebSocket transport path.
class GroqTranscriptionService extends ChangeNotifier {
  final SettingsService _settings;
  final GroqHttpClient _httpClient;
  final GroqRateLimiter _rateLimiter;

  final List<Uint8List> _chunks = [];
  int _totalBytes = 0;
  GroqTranscriptionStatus _status = GroqTranscriptionStatus.idle;

  // --- Public getters ---

  GroqTranscriptionStatus get status => _status;

  /// Whether a Groq API key is configured.
  bool get hasValidCredentials =>
      _settings.cachedGroqApiKey?.isNotEmpty ?? false;

  /// Current buffer size in bytes.
  int get bufferSizeBytes => _totalBytes;

  /// Whether the buffer has exceeded the conservative file-size ceiling.
  bool get isBufferOverLimit => _totalBytes >= AppConstants.groqMaxBufferBytes;

  // --- Constructor ---

  GroqTranscriptionService(this._settings, {GroqHttpClient? httpClient})
    : _httpClient = httpClient ?? GroqHttpClient(),
      _rateLimiter = GroqRateLimiter();

  // --- Public methods ---

  /// Appends a raw PCM chunk to the local buffer.
  ///
  /// Returns `true` if the chunk was accepted, `false` if the buffer ceiling
  /// has been reached. When `false` is returned the controller must stop
  /// recording immediately and call [finalizeAndTranscribe] on the buffered
  /// prefix — the first `false` return is definitive and no subsequent chunks
  /// will be accepted.
  bool bufferAudioChunk(Uint8List data) {
    if (_totalBytes + data.length > AppConstants.groqMaxBufferBytes) {
      LoggingService().warning(
        'Groq buffer reached ${AppConstants.groqMaxBufferBytes} bytes ceiling '
        '(~${AppConstants.groqMaxRecordingDuration.inSeconds}s) — '
        'stopping recording',
      );

      return false;
    }

    _chunks.add(data);
    _totalBytes += data.length;

    if (_status != GroqTranscriptionStatus.buffering) {
      _status = GroqTranscriptionStatus.buffering;
      notifyListeners();
    }

    return true;
  }

  /// Encodes the buffered PCM as WAV, POSTs to Groq, and returns the text.
  ///
  /// Throws [GroqError] on rate-limit violation, API errors, or network
  /// failures. The caller ([RecordingController._transcribeWithGroq]) catches
  /// this and routes it through the error stream.
  Future<String> finalizeAndTranscribe() async {
    if (_chunks.isEmpty) {
      throw const GroqError(
        type: GroqErrorType.badRequest,
        message: 'No audio data buffered',
      );
    }

    if (!_rateLimiter.canRequest()) {
      throw GroqError(
        type: GroqErrorType.rateLimited,
        message: 'Local rate limit reached',
        retryAfter: _rateLimiter.retryAfter,
      );
    }

    _status = GroqTranscriptionStatus.transcribing;
    notifyListeners();

    try {
      // Concatenate chunks into a single PCM buffer.
      final pcm = _concatenateChunks();

      // Wrap in WAV container.
      final wav = WavEncoder.encode(pcm);

      // Retrieve credentials and optional hints.
      final apiKey = await _settings.getGroqApiKey();
      if (apiKey == null || apiKey.isEmpty) {
        throw const GroqError(
          type: GroqErrorType.invalidApiKey,
          message: 'No Groq API key configured',
        );
      }

      final language = _settings.groqLanguage;
      if (!AppConstants.isValidGroqLanguage(language)) {
        throw GroqError(
          type: GroqErrorType.badRequest,
          message: 'Unsupported language code: "$language"',
        );
      }
      final prompt = _settings.groqPrompt;

      // POST to Groq.
      // Record the attempt before sending — success or failure, it consumed
      // a rate-limit slot on the server side.
      _rateLimiter.recordRequest();

      final result = await _httpClient.transcribe(
        wavBytes: wav,
        apiKey: apiKey,
        language: language.isNotEmpty ? language : null,
        prompt: prompt.isNotEmpty ? prompt : null,
      );

      // Update limiter with server-side remaining counts.
      _rateLimiter.updateFromHeaders(result.responseHeaders);

      clearBuffer();

      // Sanitize at the trust boundary — Groq output bypasses the backend
      // sanitizer, so strip ANSI escapes and control characters before the
      // text reaches clipboard/paste automation.
      return TextSanitizer.sanitize(result.text);
    } on GroqError catch (e) {
      _status = GroqTranscriptionStatus.error;
      notifyListeners();
      // Feed retry-after from 429 responses into the local limiter so the
      // next recording respects the server-mandated cool-down.
      final cooldown = e.retryAfter;
      if (cooldown != null) {
        _rateLimiter.updateFromHeaders({
          'retry-after': cooldown.inSeconds.toString(),
        });
      }
      rethrow;
    } catch (e, st) {
      _status = GroqTranscriptionStatus.error;
      notifyListeners();
      Error.throwWithStackTrace(
        GroqError(type: GroqErrorType.unknown, message: e.toString()),
        st,
      );
    }
  }

  /// Discards buffered audio without transcribing.
  void clearBuffer() {
    _chunks.clear();
    _totalBytes = 0;
    _status = GroqTranscriptionStatus.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    _httpClient.dispose();
    super.dispose();
  }

  // --- Private methods ---

  Uint8List _concatenateChunks() {
    final result = Uint8List(_totalBytes);
    var offset = 0;
    for (final chunk in _chunks) {
      result.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }

    return result;
  }
}

/// Lifecycle states for the Groq Cloud transcription engine.
enum GroqTranscriptionStatus { idle, buffering, transcribing, error }
