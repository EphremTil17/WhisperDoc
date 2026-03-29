import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_client/services/transcription/groq_transcription_service.dart';
import 'package:flutter_client/services/transcription/groq_error.dart';
import 'package:flutter_client/services/utility/settings_service.dart';

class MockSettingsService extends Mock implements SettingsService {}

void main() {
  group('GroqTranscriptionService', () {
    late GroqTranscriptionService service;
    late MockSettingsService mockSettings;

    setUp(() {
      mockSettings = MockSettingsService();
      when(() => mockSettings.cachedGroqApiKey).thenReturn('test-groq-key');
      when(() => mockSettings.groqLanguage).thenReturn('');
      when(() => mockSettings.groqPrompt).thenReturn('');
      when(
        () => mockSettings.getGroqApiKey(),
      ).thenAnswer((_) async => 'test-groq-key');

      service = GroqTranscriptionService(mockSettings);
    });

    test('starts in idle status', () {
      expect(service.status, GroqTranscriptionStatus.idle);
      expect(service.bufferSizeBytes, 0);
    });

    test('hasValidCredentials is true when key is set', () {
      expect(service.hasValidCredentials, isTrue);
    });

    test('hasValidCredentials is false when key is null', () {
      when(() => mockSettings.cachedGroqApiKey).thenReturn(null);
      final noKeyService = GroqTranscriptionService(mockSettings);

      expect(noKeyService.hasValidCredentials, isFalse);
    });

    test('hasValidCredentials is false when key is empty', () {
      when(() => mockSettings.cachedGroqApiKey).thenReturn('');
      final emptyKeyService = GroqTranscriptionService(mockSettings);

      expect(emptyKeyService.hasValidCredentials, isFalse);
    });

    test('bufferAudioChunk transitions to buffering', () {
      service.bufferAudioChunk(Uint8List(100));

      expect(service.status, GroqTranscriptionStatus.buffering);
      expect(service.bufferSizeBytes, 100);
    });

    test('bufferAudioChunk accumulates multiple chunks', () {
      service.bufferAudioChunk(Uint8List(100));
      service.bufferAudioChunk(Uint8List(200));

      expect(service.bufferSizeBytes, 300);
    });

    test('clearBuffer resets to idle', () {
      service.bufferAudioChunk(Uint8List(100));
      service.clearBuffer();

      expect(service.status, GroqTranscriptionStatus.idle);
      expect(service.bufferSizeBytes, 0);
    });

    test('finalizeAndTranscribe throws when buffer is empty', () {
      expect(
        () => service.finalizeAndTranscribe(),
        throwsA(
          isA<GroqError>().having(
            (e) => e.type,
            'type',
            GroqErrorType.badRequest,
          ),
        ),
      );
    });

    test('isBufferOverLimit is false under the limit', () {
      service.bufferAudioChunk(Uint8List(100));
      expect(service.isBufferOverLimit, isFalse);
    });
  });
}
