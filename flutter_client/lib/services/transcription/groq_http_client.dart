import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:flutter/foundation.dart';

import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import 'groq_error.dart';

/// Low-level HTTP client for the Groq Audio Transcriptions API.
///
/// Sends a WAV file as multipart/form-data and returns the transcribed text.
/// This is the only class in the transcription module that imports `package:http`.
class GroqHttpClient {
  static const int _httpOk = 200;

  final http.Client _client;

  GroqHttpClient({http.Client? client}) : _client = client ?? http.Client();

  /// Posts [wavBytes] to Groq and returns the transcription result.
  ///
  /// Throws [GroqError] on any failure (HTTP error, network error, timeout).
  Future<GroqTranscriptionResult> transcribe({
    required Uint8List wavBytes,
    required String apiKey,
    String? model,
    String? language,
    String? prompt,
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse(AppConstants.groqTranscriptionEndpoint),
      );

      request.headers['Authorization'] = 'Bearer $apiKey';

      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          wavBytes,
          filename: 'audio.wav',
          contentType: MediaType('audio', 'wav'),
        ),
      );

      request.fields['model'] = model ?? AppConstants.groqDefaultModel;
      request.fields['response_format'] = 'json';
      request.fields['temperature'] = '0';

      if (language != null && language.isNotEmpty) {
        request.fields['language'] = language;
      }
      if (prompt != null && prompt.isNotEmpty) {
        request.fields['prompt'] = prompt;
      }

      final streamed = await _client
          .send(request)
          .timeout(AppConstants.groqHttpTimeout);

      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == _httpOk) {
        final text = _extractText(response.body);

        return GroqTranscriptionResult(
          text: text,
          responseHeaders: response.headers,
        );
      }

      final error = GroqError.fromResponse(response.statusCode, response.body);

      // Attach retry-after duration for 429 responses.
      if (error.type == GroqErrorType.rateLimited) {
        final retrySeconds = int.tryParse(
          response.headers['retry-after'] ?? '',
        );
        throw GroqError(
          type: error.type,
          message: error.message,
          retryAfter: retrySeconds != null
              ? Duration(seconds: retrySeconds)
              : null,
        );
      }

      throw error;
    } on GroqError {
      rethrow;
    } on SocketException catch (e, st) {
      Error.throwWithStackTrace(GroqError.network(e.message), st);
    } on TimeoutException catch (_, st) {
      Error.throwWithStackTrace(GroqError.network('Request timed out'), st);
    } catch (e, st) {
      Error.throwWithStackTrace(
        GroqError(type: GroqErrorType.unknown, message: e.toString()),
        st,
      );
    }
  }

  void dispose() => _client.close();

  /// Extracts the `text` field from the Groq JSON response.
  /// Response shape: `{"text": "...", "x_groq": {...}}`
  String _extractText(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;

      return json['text'] as String? ?? '';
    } catch (_) {
      return body;
    }
  }
}

/// Result of a successful Groq transcription request.
class GroqTranscriptionResult {
  final String text;
  final Map<String, String> responseHeaders;

  const GroqTranscriptionResult({
    required this.text,
    required this.responseHeaders,
  });
}
