import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import 'groq_error.dart';

/// Low-level HTTP client for Groq Chat Completions API.
///
/// Sends JSON requests to Groq's OpenAI-compatible `/chat/completions` endpoint.
class GroqChatClient {
  static const int _httpOk = 200;

  final http.Client _client;

  GroqChatClient({http.Client? client}) : _client = client ?? http.Client();

  /// Posts a chat completion request to Groq and returns the text result.
  ///
  /// Throws [GroqError] on any failure (HTTP error, network error, timeout).
  Future<GroqChatResult> complete({
    required String apiKey,
    required String systemPrompt,
    required String userContent,
    required int maxCompletionTokens,
    required Duration timeout,
  }) async {
    try {
      final uri = Uri.parse(AppConstants.groqChatCompletionsEndpoint);
      final bodyMap = {
        'model': AppConstants.groqTransformModel,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {
            'role': 'user',
            'content': '<transcript>\n$userContent\n</transcript>',
          },
        ],
        'temperature': AppConstants.groqTransformTemperature,
        'max_completion_tokens': maxCompletionTokens,
        'stream': false,
        // Suppress reasoning/CoT tokens (cannot specify both include_reasoning and reasoning_format)
        'include_reasoning': false,
      };

      final response = await _client
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(bodyMap),
          )
          .timeout(timeout);

      if (response.statusCode == _httpOk) {
        final choice = _extractChoice(response.body);

        return GroqChatResult(text: choice.$1, finishReason: choice.$2);
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

  /// Extracts the assistant message content and finish_reason from the chat completion response.
  /// Response shape: `{"choices": [{"message": {"content": "..."}, "finish_reason": "..."}]}`
  (String, String?) _extractChoice(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final choices = json['choices'] as List<Object?>?;
      if (choices != null && choices.isNotEmpty) {
        final firstChoice = choices.first as Map<String, dynamic>?;
        final message = firstChoice?['message'] as Map<String, dynamic>?;
        final content = message?['content'] as String? ?? '';
        final finishReason = firstChoice?['finish_reason'] as String?;

        return (content, finishReason);
      }

      return ('', null);
    } catch (_) {
      return ('', null);
    }
  }
}

/// Result of a successful Groq chat completion request.
class GroqChatResult {
  final String text;
  final String? finishReason;

  const GroqChatResult({required this.text, this.finishReason});
}
