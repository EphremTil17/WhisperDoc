import 'package:flutter_client/services/transcription/chat_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatResult.fromCompletion', () {
    test('reads the first choice’s content and finish reason', () {
      final result = ChatResult.fromCompletion({
        'choices': [
          {
            'message': {'content': 'Clean text.'},
            'finish_reason': 'stop',
          },
          {
            'message': {'content': 'ignored'},
          },
        ],
      });

      expect(result.text, 'Clean text.');
      expect(result.finishReason, 'stop');
    });

    test('an unexpected shape is empty text, never a crash', () {
      for (final json in <Map<String, dynamic>>[
        {},
        {'choices': []},
        {
          'choices': ['x'],
        },
        {
          'choices': [
            {'message': 'flat'},
          ],
        },
        {
          'choices': [
            {
              'message': {'content': 42},
              'finish_reason': 7,
            },
          ],
        },
      ]) {
        final result = ChatResult.fromCompletion(json);

        expect(result.text, isEmpty, reason: '$json');
        expect(result.finishReason, isNull, reason: '$json');
      }
    });
  });
}
