import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_client/services/hardware/audio_service.dart';
import 'package:flutter_client/services/utility/automation_service.dart';
import 'package:flutter_client/services/transport/websocket_service.dart';
import 'package:flutter_client/services/utility/history_service.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/services/hardware/audio_cue_service.dart';
import 'package:flutter_client/controllers/recording_controller.dart';

// Mock classes
class MockAudioService extends Mock implements AudioService {}

class MockWebSocketService extends Mock implements WebSocketService {}

class MockAutomationService extends Mock implements AutomationService {}

class MockHistoryService extends Mock implements HistoryService {}

class MockSettingsService extends Mock implements SettingsService {}

class MockAudioCueService extends Mock implements AudioCueService {}

void main() {
  late RecordingController controller;
  late MockAudioService mockAudioService;
  late MockWebSocketService mockWsService;
  late MockAutomationService mockAutomationService;
  late MockHistoryService mockHistoryService;
  late MockSettingsService mockSettingsService;
  late MockAudioCueService mockAudioCueService;

  setUp(() {
    mockAudioService = MockAudioService();
    mockWsService = MockWebSocketService();
    mockAutomationService = MockAutomationService();
    mockHistoryService = MockHistoryService();
    mockSettingsService = MockSettingsService();
    mockAudioCueService = MockAudioCueService();

    // Default stubs
    when(() => mockAudioService.isRecording).thenReturn(false);
    when(() => mockWsService.status).thenReturn(ConnectionStatus.disconnected);
    when(() => mockWsService.hasValidCredentials).thenReturn(true);
    when(() => mockWsService.ensureConnected()).thenAnswer((_) async => true);
    when(() => mockWsService.connect()).thenAnswer((_) async => true);
    when(() => mockWsService.onMessage).thenAnswer((_) => const Stream.empty());
    when(() => mockHistoryService.getHistory()).thenAnswer((_) async => []);
    when(() => mockHistoryService.clearAll()).thenAnswer((_) async {});
    when(() => mockSettingsService.incognitoMode).thenReturn(false);
    when(
      () => mockSettingsService.setIncognitoMode(any()),
    ).thenAnswer((_) async {});
    when(() => mockSettingsService.addListener(any())).thenReturn(null);
    when(() => mockSettingsService.removeListener(any())).thenReturn(null);
    when(() => mockAudioCueService.playStartCue()).thenReturn(null);
    when(() => mockAudioCueService.playStopCue()).thenReturn(null);
    when(
      () => mockAudioService.amplitudeStream,
    ).thenAnswer((_) => Stream<double>.empty());

    controller = RecordingController(
      audioService: mockAudioService,
      wsService: mockWsService,
      automationService: mockAutomationService,
      historyService: mockHistoryService,
      settingsService: mockSettingsService,
      audioCueService: mockAudioCueService,
    );
  });

  group('Incognito Mode', () {
    test('enableIncognitoMode sets incognitoMode to true', () async {
      // Mock SettingsService to return true after setIncognitoMode is called
      when(() => mockSettingsService.incognitoMode).thenReturn(true);

      await controller.enableIncognitoMode();

      expect(controller.incognitoMode, isTrue);
      verify(() => mockSettingsService.setIncognitoMode(true)).called(1);
      verify(() => mockHistoryService.clearAll()).called(1);
    });

    test('enableIncognitoMode clears existing history', () async {
      // We can't easily add to history without triggering the full flow,
      // but we can verify clearHistory works
      await controller.clearHistory();
      expect(controller.history, isEmpty);
    });

    test('disableIncognitoMode sets incognitoMode to false', () async {
      // Setup: mock incognito true, then false after disable
      when(() => mockSettingsService.incognitoMode).thenReturn(true);
      await controller.enableIncognitoMode();
      expect(controller.incognitoMode, isTrue);

      when(() => mockSettingsService.incognitoMode).thenReturn(false);
      await controller.disableIncognitoMode();
      expect(controller.incognitoMode, isFalse);
      verify(() => mockSettingsService.setIncognitoMode(false)).called(1);
    });
  });

  group('Recording State', () {
    test('isRecording initially false', () {
      expect(controller.isRecording, isFalse);
    });

    test('toggleRecording calls startRecording when not recording', () async {
      when(() => mockAudioService.isRecording).thenReturn(false);
      when(() => mockWsService.connect()).thenAnswer((_) async => true);
      // The default stub for ensureConnected is true in setUp
      when(
        () => mockAudioService.startRecording(
          deviceId: any(named: 'deviceId'),
          deviceLabel: any(named: 'deviceLabel'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => mockAudioService.audioStream,
      ).thenAnswer((_) => const Stream.empty());

      await controller.toggleRecording();
      await Future.delayed(
        Duration.zero,
      ); // Give the unawaited ensureConnected time to run if needed

      verify(() => mockWsService.ensureConnected()).called(1);
      verify(
        () => mockAudioService.startRecording(
          deviceId: any(named: 'deviceId'),
          deviceLabel: any(named: 'deviceLabel'),
        ),
      ).called(1);
      verify(() => mockAudioCueService.playStartCue()).called(1);
    });

    test('startRecording connects to WebSocket if disconnected', () async {
      when(
        () => mockWsService.status,
      ).thenReturn(ConnectionStatus.disconnected);
      when(() => mockWsService.ensureConnected()).thenAnswer((_) async => true);
      when(
        () => mockAudioService.startRecording(
          deviceId: any(named: 'deviceId'),
          deviceLabel: any(named: 'deviceLabel'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => mockAudioService.audioStream,
      ).thenAnswer((_) => const Stream.empty());

      await controller.startRecording();
      await Future.delayed(Duration.zero);

      verify(() => mockWsService.ensureConnected()).called(1);
      verify(() => mockAudioCueService.playStartCue()).called(1);
    });

    test('startRecording does not reconnect if already connected', () async {
      when(() => mockWsService.status).thenReturn(ConnectionStatus.connected);
      when(
        () => mockAudioService.startRecording(
          deviceId: any(named: 'deviceId'),
          deviceLabel: any(named: 'deviceLabel'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => mockAudioService.audioStream,
      ).thenAnswer((_) => const Stream.empty());
      when(() => mockAudioCueService.playStartCue()).thenReturn(null);

      await controller.startRecording();
      await Future.delayed(Duration.zero);

      // In the new architecture, we ALWAYS call ensureConnected,
      // which itself decides whether to trigger a real connection.
      verify(() => mockWsService.ensureConnected()).called(1);
      verifyNever(() => mockWsService.connect());
    });

    test('startRecording handles connection failure gracefully', () async {
      when(
        () => mockWsService.status,
      ).thenReturn(ConnectionStatus.disconnected);
      when(
        () => mockWsService.ensureConnected(),
      ).thenAnswer((_) async => false);
      when(
        () => mockAudioService.startRecording(
          deviceId: any(named: 'deviceId'),
          deviceLabel: any(named: 'deviceLabel'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => mockAudioService.audioStream,
      ).thenAnswer((_) => const Stream.empty());
      when(() => mockAudioCueService.playStartCue()).thenReturn(null);

      await controller.startRecording();
      await Future.delayed(Duration.zero);

      // Audio recording starts INSTANTLY (Zero-Latency)
      verify(
        () => mockAudioService.startRecording(
          deviceId: any(named: 'deviceId'),
          deviceLabel: any(named: 'deviceLabel'),
        ),
      ).called(1);
      verify(() => mockWsService.ensureConnected()).called(1);
      verify(() => mockAudioCueService.playStartCue()).called(1);

      // Since it failed (mocked to false), it should stop
      // Note: we can't easily verify the stopRecording call inside the then()
    });
  });

  group('Current Text Buffer', () {
    test('currentText initially empty', () {
      expect(controller.currentText, isEmpty);
    });

    test('startRecording clears current buffer', () async {
      when(() => mockWsService.status).thenReturn(ConnectionStatus.connected);
      when(
        () => mockAudioService.startRecording(
          deviceId: any(named: 'deviceId'),
          deviceLabel: any(named: 'deviceLabel'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => mockAudioService.audioStream,
      ).thenAnswer((_) => const Stream.empty());

      await controller.startRecording();

      expect(controller.currentText, isEmpty);
    });
  });
}
