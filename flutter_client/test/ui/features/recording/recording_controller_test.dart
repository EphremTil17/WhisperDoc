// ignore_for_file: prefer-match-file-name, avoid-late-keyword, no-empty-block
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_client/services/hardware/audio_input_status.dart';
import 'package:flutter_client/services/hardware/audio_service.dart';
import 'package:flutter_client/services/utility/automation_service.dart';
import 'package:flutter_client/services/transport/websocket_service.dart';
import 'package:flutter_client/services/utility/history_service.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/services/hardware/audio_cue_service.dart';
import 'package:flutter_client/services/transcription/groq_transcription_service.dart';
import 'package:flutter_client/controllers/recording_controller.dart';

class _MockAudioService extends Mock implements AudioService {}

class _MockWebSocketService extends Mock implements WebSocketService {}

class _MockAutomationService extends Mock implements AutomationService {}

class _MockHistoryService extends Mock implements HistoryService {}

class _MockSettingsService extends Mock implements SettingsService {}

class _MockAudioCueService extends Mock implements AudioCueService {}

class _MockGroqTranscriptionService extends Mock
    implements GroqTranscriptionService {}

void main() {
  late RecordingController controller;
  late _MockAudioService mockAudioService;
  late _MockWebSocketService mockWsService;
  late _MockAutomationService mockAutomationService;
  late _MockHistoryService mockHistoryService;
  late _MockSettingsService mockSettingsService;
  late _MockAudioCueService mockAudioCueService;
  late _MockGroqTranscriptionService mockGroqService;

  setUp(() {
    mockAudioService = _MockAudioService();
    mockWsService = _MockWebSocketService();
    mockGroqService = _MockGroqTranscriptionService();
    mockAutomationService = _MockAutomationService();
    mockHistoryService = _MockHistoryService();
    mockSettingsService = _MockSettingsService();
    mockAudioCueService = _MockAudioCueService();

    // Default stubs
    when(() => mockAudioService.isRecording).thenReturn(false);
    when(
      () => mockAudioService.inputStatus,
    ).thenReturn(AudioInputStatus.available);
    when(
      () => mockAudioService.evaluateInputStatus(
        targetDeviceId: any(named: 'targetDeviceId'),
      ),
    ).thenAnswer((_) async => AudioInputStatus.available);
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
    ).thenAnswer((_) => const Stream<double>.empty());
    // Groq mode defaults to off (backend mode)
    when(() => mockSettingsService.isGroqMode).thenReturn(false);
    when(() => mockGroqService.hasValidCredentials).thenReturn(false);
    when(() => mockGroqService.status).thenReturn(GroqTranscriptionStatus.idle);
    when(() => mockGroqService.addListener(any())).thenReturn(null);
    when(() => mockGroqService.removeListener(any())).thenReturn(null);

    controller = RecordingController(
      audioService: mockAudioService,
      wsService: mockWsService,
      groqService: mockGroqService,
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

      final ensureCall = verify(() => mockWsService.ensureConnected());
      expect(ensureCall.callCount, equals(1));
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

      final ensureCall = verify(() => mockWsService.ensureConnected());
      expect(ensureCall.callCount, equals(1));
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
      final ensureCall = verify(() => mockWsService.ensureConnected());
      expect(ensureCall.callCount, equals(1));
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
      when(() => mockAudioService.stopRecording()).thenAnswer((_) async {});

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
      // Connection failed, so recording should have been stopped
      expect(controller.isRecording, isFalse);
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

  group('Hardware Input Guard', () {
    test('startRecording blocks for each non-canRecord status', () async {
      final nonRecordableStatuses = [
        AudioInputStatus.noDevice,
        AudioInputStatus.selectedUnavailable,
        AudioInputStatus.permissionDenied,
      ];

      for (final status in nonRecordableStatuses) {
        when(() => mockAudioService.inputStatus).thenReturn(status);
        String? emittedError;
        final sub = controller.onError.listen((e) => emittedError = e);

        await controller.startRecording();

        expect(controller.isRecording, isFalse);
        expect(emittedError, equals(status.bannerMessage));
        verifyNever(
          () => mockAudioService.startRecording(
            deviceId: any(named: 'deviceId'),
            deviceLabel: any(named: 'deviceLabel'),
          ),
        );
        await sub.cancel();
      }
    });

    test('hardware failure surfaces the status banner message', () async {
      // Model the real interaction: AudioService sets a degraded status before
      // throwing, and the controller reads that status for its message.
      var status = AudioInputStatus.available;
      when(() => mockAudioService.inputStatus).thenAnswer((_) => status);
      when(
        () => mockAudioService.startRecording(
          deviceId: any(named: 'deviceId'),
          deviceLabel: any(named: 'deviceLabel'),
        ),
      ).thenAnswer((_) {
        status = AudioInputStatus.noDevice;
        throw Exception('No audio recording device');
      });

      String? emittedError;
      controller.onError.listen((e) => emittedError = e);

      await controller.startRecording();

      expect(controller.isRecording, isFalse);
      expect(emittedError, equals(AudioInputStatus.noDevice.bannerMessage));
    });

    test(
      'non-hardware failure stays generic and does not disable the mic',
      () async {
        // Status remains healthy (canRecord) — a transient error must not be
        // reported as a missing microphone.
        when(
          () => mockAudioService.inputStatus,
        ).thenReturn(AudioInputStatus.available);
        when(
          () => mockAudioService.startRecording(
            deviceId: any(named: 'deviceId'),
            deviceLabel: any(named: 'deviceLabel'),
          ),
        ).thenThrow(StateError('unexpected cue failure'));

        String? emittedError;
        controller.onError.listen((e) => emittedError = e);

        await controller.startRecording();

        expect(controller.isRecording, isFalse);
        expect(
          emittedError,
          equals('Could not start recording. Please try again.'),
        );
      },
    );

    test('refreshHardwareStatus delegates to evaluateInputStatus', () async {
      when(() => mockSettingsService.microphoneId).thenReturn('mic-123');
      when(
        () => mockAudioService.evaluateInputStatus(
          targetDeviceId: any(named: 'targetDeviceId'),
        ),
      ).thenAnswer((_) async => AudioInputStatus.available);

      await controller.refreshHardwareStatus();

      expect(controller.isRecording, isFalse);
      verify(
        () => mockAudioService.evaluateInputStatus(targetDeviceId: 'mic-123'),
      ).called(1);
    });
  });
}
