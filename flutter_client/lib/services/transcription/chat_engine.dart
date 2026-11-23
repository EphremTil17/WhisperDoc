import 'package:flutter_client/logic/models/transcription_source.dart';

/// A cloud LLM the output styles rewrite a transcript with.
abstract interface class ChatEngine {
  TranscriptionSource get source;

  /// One system prompt, one user message (the transcript, already wrapped).
  /// Throws `CloudError`.
  Future<ChatResult> complete({
    required String systemPrompt,
    required String userContent,
    required int maxTokens,
    required Duration timeout,
  });
}

/// The rewritten text and why generation stopped (`length` means cut off).
class ChatResult {
  const ChatResult({required this.text, this.finishReason});

  /// Reads `choices[0].message.content` and `finish_reason` from an
  /// OpenAI-shaped chat completion; empty text when the shape differs.
  factory ChatResult.fromCompletion(Map<String, dynamic> json) {
    final choices = json['choices'];
    final first = choices is List && choices.isNotEmpty ? choices.first : null;
    if (first is! Map<String, dynamic>) return const ChatResult(text: '');
    final message = first['message'];
    final content = message is Map<String, dynamic> ? message['content'] : null;
    final reason = first['finish_reason'];

    return ChatResult(
      text: content is String ? content : '',
      finishReason: reason is String ? reason : null,
    );
  }

  final String text;
  final String? finishReason;
}
