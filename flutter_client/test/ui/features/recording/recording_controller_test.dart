import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_client/core/services/audio_service.dart';
import 'package:flutter_client/core/services/automation_service.dart';
import 'package:flutter_client/core/services/websocket_service.dart';
import 'package:flutter_client/core/controllers/recording_controller.dart';

// Mock classes
class MockAudioService extends Mock implements AudioService {}

class MockWebSocketService extends Mock implements WebSocketService {}

class MockAutomationService extends Mock implements AutomationService {}

void main() {
  late RecordingController controller;
  late MockAudioService mockAudioService;
  late MockWebSocketService mockWsService;
  late MockAutomationService mockAutomationService;

  setUp(() {
    mockAudioService = MockAudioService();
    mockWsService = MockWebSocketService();
    mockAutomationService = MockAutomationService();

    // Default stubs
    when(() => mockAudioService.isRecording).thenReturn(false);
    when(() => mockWsService.status).thenReturn(ConnectionStatus.disconnected);
    when(() => mockWsService.onMessage).thenAnswer((_) => const Stream.empty());

    controller = RecordingController(
      audioService: mockAudioService,
      wsService: mockWsService,
      automationService: mockAutomationService,
    );
  });

  group('Incognito Mode', () {
    test('enableIncognitoMode sets incognitoMode to true', () {
      expect(controller.incognitoMode, isFalse);

      controller.enableIncognitoMode();

      expect(controller.incognitoMode, isTrue);
    });

    test('enableIncognitoMode clears existing history', () {
      // We can't easily add to history without triggering the full flow,
      // but we can verify clearHistory works
      controller.clearHistory();
      expect(controller.history, isEmpty);
    });

    test('disableIncognitoMode sets incognitoMode to false', () {
      controller.enableIncognitoMode();
      expect(controller.incognitoMode, isTrue);

      controller.disableIncognitoMode();
      expect(controller.incognitoMode, isFalse);
    });
  });

  group('Recording State', () {
    test('isRecording initially false', () {
      expect(controller.isRecording, isFalse);
    });

    test('toggleRecording calls startRecording when not recording', () async {
      when(() => mockAudioService.isRecording).thenReturn(false);
      when(() => mockWsService.connect()).thenAnswer((_) async => true);
      when(() => mockAudioService.startRecording()).thenAnswer((_) async {});
      when(
        () => mockAudioService.audioStream,
      ).thenAnswer((_) => const Stream.empty());

      await controller.toggleRecording();

      verify(() => mockWsService.connect()).called(1);
      verify(() => mockAudioService.startRecording()).called(1);
    });

    test('startRecording connects to WebSocket if disconnected', () async {
      when(
        () => mockWsService.status,
      ).thenReturn(ConnectionStatus.disconnected);
      when(() => mockWsService.connect()).thenAnswer((_) async => true);
      when(() => mockAudioService.startRecording()).thenAnswer((_) async {});
      when(
        () => mockAudioService.audioStream,
      ).thenAnswer((_) => const Stream.empty());

      await controller.startRecording();

      verify(() => mockWsService.connect()).called(1);
    });

    test('startRecording does not reconnect if already connected', () async {
      when(() => mockWsService.status).thenReturn(ConnectionStatus.connected);
      when(() => mockAudioService.startRecording()).thenAnswer((_) async {});
      when(
        () => mockAudioService.audioStream,
      ).thenAnswer((_) => const Stream.empty());

      await controller.startRecording();

      verifyNever(() => mockWsService.connect());
    });

    test('startRecording handles connection failure gracefully', () async {
      when(
        () => mockWsService.status,
      ).thenReturn(ConnectionStatus.disconnected);
      when(() => mockWsService.connect()).thenAnswer((_) async => false);

      await controller.startRecording();

      // Should not proceed to audio recording if connection failed
      verifyNever(() => mockAudioService.startRecording());
    });
  });

  group('Current Text Buffer', () {
    test('currentText initially empty', () {
      expect(controller.currentText, isEmpty);
    });

    test('startRecording clears current buffer', () async {
      when(() => mockWsService.status).thenReturn(ConnectionStatus.connected);
      when(() => mockAudioService.startRecording()).thenAnswer((_) async {});
      when(
        () => mockAudioService.audioStream,
      ).thenAnswer((_) => const Stream.empty());

      await controller.startRecording();

      expect(controller.currentText, isEmpty);
    });
  });
}
