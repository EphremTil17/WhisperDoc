import 'package:flutter_client/logic/models/transcription_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TranscriptionSource', () {
    test('keeps the storage keys earlier versions saved', () {
      expect(TranscriptionSource.server.storageKey, 'backend');
      expect(TranscriptionSource.groq.storageKey, 'groq');
      expect(TranscriptionSource.openRouter.storageKey, 'openrouter');
    });

    test('reads every stored key back, and anything else as the server', () {
      for (final source in TranscriptionSource.values) {
        expect(TranscriptionSource.fromStorageKey(source.storageKey), source);
      }
      expect(
        TranscriptionSource.fromStorageKey(null),
        TranscriptionSource.server,
      );
      expect(
        TranscriptionSource.fromStorageKey('Groq'),
        TranscriptionSource.server,
      );
    });

    test('only the server is not a cloud source', () {
      expect(TranscriptionSource.server.isCloud, isFalse);
      expect(TranscriptionSource.groq.isCloud, isTrue);
      expect(TranscriptionSource.openRouter.isCloud, isTrue);
    });

    test('labels name the service in messages', () {
      expect(TranscriptionSource.server.label, 'WhisperDoc server');
      expect(TranscriptionSource.groq.label, 'Groq');
      expect(TranscriptionSource.openRouter.label, 'OpenRouter');
    });
  });
}
