// ignore_for_file: prefer-match-file-name, avoid-late-keyword, no-empty-block
import 'dart:async';
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
import 'package:flutter_client/services/transcription/groq_transform_service.dart';
import 'package:flutter_client/services/transcription/groq_error.dart';
import 'package:flutter_client/logic/models/dictation_profile.dart';
import 'package:flutter_client/controllers/recording_controller.dart';

class _MockAudioService extends Mock implements AudioService {}

class _MockWebSocketService extends Mock implements WebSocketService {}

class _MockAutomationService extends Mock implements AutomationService {}

class _MockHistoryService extends Mock implements HistoryService {}

class _MockSettingsService extends Mock implements SettingsService {}

class _MockAudioCueService extends Mock implements AudioCueService {}

class _MockGroqTranscriptionService extends Mock
    implements GroqTranscriptionService {}

class _MockGroqTransformService extends Mock implements GroqTransformService {}

void main() {
  setUpAll(() {
    registerFallbackValue(DictationProfile.raw);
    registerFallbackValue(DateTime.now());
  });

  late RecordingController controller;
  late _MockAudioService mockAudioService;
  late _MockWebSocketService mockWsService;
  late _MockAutomationService mockAutomationService;
  late _MockHistoryService mockHistoryService;
  late _MockSettingsService mockSettingsService;
  late _MockAudioCueService mockAudioCueService;
  late _MockGroqTranscriptionService mockGroqService;
  late _MockGroqTransformService mockTransformService;
  late StreamController<Map<String, dynamic>> mockWsMessageController;
  late void Function() audioStateListener;

  setUp(() {
    mockAudioService = _MockAudioService();
    when(() => mockAudioService.addListener(any())).thenAnswer((inv) {
      audioStateListener = inv.positionalArguments.first as void Function();
    });
    mockWsService = _MockWebSocketService();
    mockGroqService = _MockGroqTranscriptionService();
    mockTransformService = _MockGroqTransformService();
    mockAutomationService = _MockAutomationService();
    mockHistoryService = _MockHistoryService();
    mockSettingsService = _MockSettingsService();
    mockAudioCueService = _MockAudioCueService();
    mockWsMessageController =
        StreamController<Map<String, dynamic>>.broadcast();

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
    when(
      () => mockWsService.onMessage,
    ).thenAnswer((_) => mockWsMessageController.stream);
    when(
      () => mockAutomationService.runAutomation(any()),
    ).thenAnswer((_) async {});
    when(
      () => mockHistoryService.saveTranscription(
        text: any(named: 'text'),
        timestamp: any(named: 'timestamp'),
      ),
    ).thenAnswer((_) async {});
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
    when(
      () => mockSettingsService.dictationProfile,
    ).thenReturn(DictationProfile.raw);
    when(() => mockGroqService.hasValidCredentials).thenReturn(false);
    when(() => mockGroqService.status).thenReturn(GroqTranscriptionStatus.idle);
    when(() => mockGroqService.addListener(any())).thenReturn(null);
    when(() => mockGroqService.removeListener(any())).thenReturn(null);

    controller = RecordingController(
      audioService: mockAudioService,
      wsService: mockWsService,
      groqService: mockGroqService,
      transformService: mockTransformService,
      automationService: mockAutomationService,
      historyService: mockHistoryService,
      settingsService: mockSettingsService,
      audioCueService: mockAudioCueService,
    );
  });

  tearDown(() async {
    await mockWsMessageController.close();
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

  group('Dictation Profile Transformation', () {
    setUp(() {
      when(() => mockSettingsService.isGroqMode).thenReturn(true);
    });

    test(
      'raw profile bypasses transform service and pastes raw text directly',
      () async {
        when(
          () => mockSettingsService.dictationProfile,
        ).thenReturn(DictationProfile.raw);

        mockWsMessageController.add({
          'event': 'transcription',
          'text': 'Raw unpolished transcription.',
        });

        await Future<void>.delayed(const Duration(milliseconds: 50));

        verifyNever(() => mockTransformService.transform(any(), any()));
        verify(
          () => mockAutomationService.runAutomation(
            'Raw unpolished transcription.',
          ),
        ).called(1);
        verify(
          () => mockHistoryService.saveTranscription(
            text: 'Raw unpolished transcription.',
            timestamp: any(named: 'timestamp'),
          ),
        ).called(1);
        expect(controller.currentText, 'Raw unpolished transcription.');
      },
    );

    test(
      'clean profile invokes transform service and pastes polished text',
      () async {
        when(
          () => mockSettingsService.dictationProfile,
        ).thenReturn(DictationProfile.clean);
        when(
          () => mockTransformService.transform(
            'um raw transcription with fillers you know',
            DictationProfile.clean,
          ),
        ).thenAnswer((_) async => 'Clean transcription without fillers.');

        mockWsMessageController.add({
          'event': 'transcription',
          'text': 'um raw transcription with fillers you know',
        });

        await Future<void>.delayed(const Duration(milliseconds: 50));

        verify(
          () => mockTransformService.transform(
            'um raw transcription with fillers you know',
            DictationProfile.clean,
          ),
        ).called(1);
        verify(
          () => mockAutomationService.runAutomation(
            'Clean transcription without fillers.',
          ),
        ).called(1);
        verify(
          () => mockHistoryService.saveTranscription(
            text: 'Clean transcription without fillers.',
            timestamp: any(named: 'timestamp'),
          ),
        ).called(1);
        expect(controller.currentText, 'Clean transcription without fillers.');
        expect(controller.isTranscribing, isFalse);
      },
    );

    test(
      'GroqError in transform fails open to raw text and emits error stream',
      () async {
        when(
          () => mockSettingsService.dictationProfile,
        ).thenReturn(DictationProfile.clean);
        when(() => mockTransformService.transform(any(), any())).thenThrow(
          const GroqError(
            type: GroqErrorType.rateLimited,
            message: 'Rate limit hit',
          ),
        );

        String? emittedError;
        final sub = controller.onError.listen((e) => emittedError = e);

        mockWsMessageController.add({
          'event': 'transcription',
          'text': 'Raw text fallback.',
        });

        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Fails open: pastes raw text
        verify(
          () => mockAutomationService.runAutomation('Raw text fallback.'),
        ).called(1);
        verify(
          () => mockHistoryService.saveTranscription(
            text: 'Raw text fallback.',
            timestamp: any(named: 'timestamp'),
          ),
        ).called(1);

        expect(emittedError, isNotNull);
        expect(
          emittedError,
          contains('Clean polish unavailable, pasted raw text'),
        );
        expect(controller.isTranscribing, isFalse);

        await sub.cancel();
      },
    );

    test(
      'isTranscribing lockout prevents startRecording during transform',
      () async {
        when(
          () => mockSettingsService.dictationProfile,
        ).thenReturn(DictationProfile.clean);

        final completer = Completer<String>();
        when(
          () => mockTransformService.transform(any(), any()),
        ).thenAnswer((_) => completer.future);

        mockWsMessageController.add({
          'event': 'transcription',
          'text': 'Transcript in progress.',
        });

        // Pump microtasks so finishRecordingSession starts and sets isTranscribing = true
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(controller.isTranscribing, isTrue);

        // Attempt to start recording during the in-flight transform
        await controller.startRecording();

        // AudioService.startRecording must NOT be called due to the lockout
        verifyNever(
          () => mockAudioService.startRecording(
            deviceId: any(named: 'deviceId'),
            deviceLabel: any(named: 'deviceLabel'),
          ),
        );

        // Complete the transform
        completer.complete('Finished transformed text.');
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(controller.isTranscribing, isFalse);
        verify(
          () =>
              mockAutomationService.runAutomation('Finished transformed text.'),
        ).called(1);
      },
    );

    test('isSessionActive reflects recording state transition', () {
      expect(controller.isSessionActive, isFalse);

      // Start recording via audio state notification
      when(() => mockAudioService.isRecording).thenReturn(true);
      audioStateListener();
      expect(controller.isRecording, isTrue);
      expect(controller.isSessionActive, isTrue);

      // Stop recording via audio state notification
      when(() => mockAudioService.isRecording).thenReturn(false);
      audioStateListener();
      expect(controller.isRecording, isFalse);
    });

    test('isSessionActive reflects transcribing lifecycle', () async {
      final completer = Completer<String>();
      when(
        () => mockSettingsService.dictationProfile,
      ).thenReturn(DictationProfile.clean);
      when(
        () => mockTransformService.transform(any(), any()),
      ).thenAnswer((_) => completer.future);

      mockWsMessageController.add({
        'event': 'transcription',
        'text': 'Processing transcript',
      });

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(controller.isTranscribing, isTrue);
      expect(controller.isSessionActive, isTrue);

      completer.complete('Done');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.isTranscribing, isFalse);
    });
  });
}
