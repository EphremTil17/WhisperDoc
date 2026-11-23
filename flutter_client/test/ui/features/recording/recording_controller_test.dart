// ignore_for_file: prefer-match-file-name, avoid-late-keyword, prefer-moving-to-variable
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_client/services/hardware/audio_device_monitor.dart';
import 'package:flutter_client/services/hardware/audio_input_status.dart';
import 'package:flutter_client/services/hardware/audio_service.dart';
import 'package:flutter_client/services/utility/automation_service.dart';
import 'package:flutter_client/services/transport/server_problem.dart';
import 'package:flutter_client/services/transport/websocket_service.dart';
import 'package:flutter_client/services/utility/history_service.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/services/hardware/audio_cue_service.dart';
import 'package:flutter_client/services/transcription/cloud_error.dart';
import 'package:flutter_client/services/transcription/cloud_transcription_service.dart';
import 'package:flutter_client/services/transcription/transform_service.dart';
import 'package:flutter_client/logic/models/transcription_source.dart';
import 'package:flutter_client/logic/models/dictation_profile.dart';
import 'package:flutter_client/controllers/recording_controller.dart';

class _MockAudioService extends Mock implements AudioService {}

class _MockWebSocketService extends Mock implements WebSocketService {}

class _MockAutomationService extends Mock implements AutomationService {}

class _MockHistoryService extends Mock implements HistoryService {}

class _MockSettingsService extends Mock implements SettingsService {}

class _MockAudioCueService extends Mock implements AudioCueService {}

class _MockCloudTranscriptionService extends Mock
    implements CloudTranscriptionService {}

class _MockTransformService extends Mock implements TransformService {}

class _MockAudioDeviceMonitor extends Mock implements AudioDeviceMonitor {}

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
  late _MockCloudTranscriptionService mockCloudService;
  late _MockTransformService mockTransformService;
  late StreamController<Map<String, dynamic>> mockWsMessageController;
  late StreamController<ConnectionStatus> wsStatusController;
  late StreamController<void> deviceChangeController;
  late void Function() audioStateListener;

  setUp(() {
    mockAudioService = _MockAudioService();
    when(() => mockAudioService.addListener(any())).thenAnswer((inv) {
      audioStateListener = inv.positionalArguments.first as void Function();
    });
    mockWsService = _MockWebSocketService();
    mockCloudService = _MockCloudTranscriptionService();
    mockTransformService = _MockTransformService();
    mockAutomationService = _MockAutomationService();
    mockHistoryService = _MockHistoryService();
    mockSettingsService = _MockSettingsService();
    mockAudioCueService = _MockAudioCueService();
    mockWsMessageController =
        StreamController<Map<String, dynamic>>.broadcast();
    wsStatusController = StreamController<ConnectionStatus>.broadcast();
    deviceChangeController = StreamController<void>.broadcast();
    final mockDeviceMonitor = _MockAudioDeviceMonitor();
    when(() => mockDeviceMonitor.changes)
        .thenAnswer((_) => deviceChangeController.stream);

    // Default stubs
    when(() => mockAudioService.isRecording).thenReturn(false);
    when(() => mockAudioService.inputStatus)
        .thenReturn(AudioInputStatus.available);
    when(
      () => mockAudioService.evaluateInputStatus(
        targetDeviceId: any(named: 'targetDeviceId'),
      ),
    ).thenAnswer((_) async => AudioInputStatus.available);
    when(() => mockWsService.status).thenReturn(ConnectionStatus.disconnected);
    when(() => mockWsService.hasValidCredentials).thenReturn(true);
    when(() => mockWsService.ensureConnected()).thenAnswer((_) async => true);
    when(() => mockWsService.connect()).thenAnswer((_) async => true);
    when(() => mockWsService.onMessage)
        .thenAnswer((_) => mockWsMessageController.stream);
    when(() => mockWsService.onStatusChanged)
        .thenAnswer((_) => wsStatusController.stream);
    when(() => mockWsService.serverProblem).thenReturn(ServerProblem.none);
    when(() => mockWsService.sendEndSignal()).thenReturn(true);
    when(() => mockAutomationService.runAutomation(any()))
        .thenAnswer((_) => Future.value());
    when(
      () => mockHistoryService.saveTranscription(
        text: any(named: 'text'),
        timestamp: any(named: 'timestamp'),
      ),
    ).thenAnswer((_) => Future.value());
    when(() => mockHistoryService.getHistory()).thenAnswer((_) async => []);
    when(() => mockHistoryService.clearAll()).thenAnswer((_) => Future.value());
    when(() => mockSettingsService.incognitoMode).thenReturn(false);
    when(() => mockSettingsService.setIncognitoMode(any()))
        .thenAnswer((_) => Future.value());
    when(() => mockSettingsService.addListener(any())).thenReturn(null);
    when(() => mockSettingsService.removeListener(any())).thenReturn(null);
    when(() => mockAudioCueService.playStartCue()).thenReturn(null);
    when(() => mockAudioCueService.playStopCue()).thenReturn(null);
    when(() => mockAudioService.amplitudeStream)
        .thenAnswer((_) => const Stream<double>.empty());
    // The server transcribes unless a test picks a cloud source.
    when(() => mockSettingsService.transcriptionSource)
        .thenReturn(TranscriptionSource.server);
    when(() => mockSettingsService.openRouterModel).thenReturn(null);
    when(() => mockSettingsService.dictationProfile)
        .thenReturn(DictationProfile.raw);
    when(() => mockCloudService.setupProblem).thenReturn(null);
    when(() => mockCloudService.maxClipDuration)
        .thenReturn(const Duration(minutes: 12, seconds: 30));

    controller = RecordingController(
      audioService: mockAudioService,
      wsService: mockWsService,
      cloudService: mockCloudService,
      transformService: mockTransformService,
      automationService: mockAutomationService,
      historyService: mockHistoryService,
      settingsService: mockSettingsService,
      audioCueService: mockAudioCueService,
      deviceMonitor: mockDeviceMonitor,
    );
  });

  tearDown(() async {
    await mockWsMessageController.close();
    await wsStatusController.close();
    await deviceChangeController.close();
  });

  /// Ends a server-mode dictation the way the recorder does, so the
  /// controller is waiting for its transcript.
  Future<void> endServerDictation() async {
    when(() => mockSettingsService.transcriptionSource)
        .thenReturn(TranscriptionSource.server);
    when(() => mockAudioService.isRecording).thenReturn(true);
    audioStateListener();
    when(() => mockAudioService.isRecording).thenReturn(false);
    audioStateListener();
    await pumpEventQueue();
  }

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
      ).thenAnswer((_) => Future.value());
      when(() => mockAudioService.audioStream)
          .thenAnswer((_) => const Stream.empty());

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
      when(() => mockWsService.status)
          .thenReturn(ConnectionStatus.disconnected);
      when(() => mockWsService.ensureConnected()).thenAnswer((_) async => true);
      when(
        () => mockAudioService.startRecording(
          deviceId: any(named: 'deviceId'),
          deviceLabel: any(named: 'deviceLabel'),
        ),
      ).thenAnswer((_) => Future.value());
      when(() => mockAudioService.audioStream)
          .thenAnswer((_) => const Stream.empty());

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
      ).thenAnswer((_) => Future.value());
      when(() => mockAudioService.audioStream)
          .thenAnswer((_) => const Stream.empty());
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
      when(() => mockWsService.status)
          .thenReturn(ConnectionStatus.disconnected);
      when(() => mockWsService.ensureConnected())
          .thenAnswer((_) async => false);
      when(
        () => mockAudioService.startRecording(
          deviceId: any(named: 'deviceId'),
          deviceLabel: any(named: 'deviceLabel'),
        ),
      ).thenAnswer((_) => Future.value());
      when(() => mockAudioService.audioStream)
          .thenAnswer((_) => const Stream.empty());
      when(() => mockAudioCueService.playStartCue()).thenReturn(null);
      when(() => mockAudioService.stopRecording())
          .thenAnswer((_) => Future.value());

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

  group('Start/stop re-entry', () {
    test('overlapping stop requests end the stream exactly once', () async {
      // Buffer-cap path + hotkey can both ask to stop mid-shutdown.
      final recorderStopped = Completer<void>();
      when(() => mockAudioService.isRecording).thenReturn(true);
      when(() => mockAudioService.stopRecording())
          .thenAnswer((_) => recorderStopped.future);
      when(() => mockWsService.sendEndSignal()).thenReturn(true);

      final first = controller.stopRecording();
      final second = controller.stopRecording();
      recorderStopped.complete();
      await Future.wait([first, second]);

      final stops = verify(() => mockAudioService.stopRecording());
      expect(stops.callCount, equals(1));
      final endSignals = verify(() => mockWsService.sendEndSignal());
      expect(endSignals.callCount, equals(1));
    });

    test('a second press while starting stops once the start lands', () async {
      // "Start, never mind": the second press must not be dropped.
      final captureStarted = Completer<void>();
      when(
        () => mockAudioService.startRecording(
          deviceId: any(named: 'deviceId'),
          deviceLabel: any(named: 'deviceLabel'),
        ),
      ).thenAnswer((_) => captureStarted.future);
      when(() => mockAudioService.audioStream)
          .thenAnswer((_) => const Stream.empty());
      when(() => mockAudioService.stopRecording()).thenAnswer((_) {
        when(() => mockAudioService.isRecording).thenReturn(false);

        return Future.value();
      });
      when(() => mockWsService.sendEndSignal()).thenReturn(true);

      final start = controller.toggleRecording();
      final secondPress = controller.toggleRecording();
      when(() => mockAudioService.isRecording).thenReturn(true);
      captureStarted.complete();
      await Future.wait([start, secondPress]);

      final stops = verify(() => mockAudioService.stopRecording());
      expect(stops.callCount, 1);
      verify(() => mockWsService.sendEndSignal()).called(1);
    });

    test(
      'a recorder that stops by itself still finishes the capture',
      () async {
        // A device error stops the recorder without stopRecording(): what was
        // captured must still be sent, and the stream dropped.
        when(() => mockWsService.sendEndSignal()).thenReturn(true);
        when(() => mockAudioService.isRecording).thenReturn(true);
        audioStateListener();
        expect(controller.isRecording, isTrue);

        when(() => mockAudioService.isRecording).thenReturn(false);
        audioStateListener();
        await pumpEventQueue();

        expect(controller.isRecording, isFalse);
        verify(() => mockAudioCueService.playStopCue()).called(1);
        verify(() => mockWsService.sendEndSignal()).called(1);
      },
    );

    test('overlapping start requests open one capture stream', () async {
      final captureStarted = Completer<void>();
      when(
        () => mockAudioService.startRecording(
          deviceId: any(named: 'deviceId'),
          deviceLabel: any(named: 'deviceLabel'),
        ),
      ).thenAnswer((_) => captureStarted.future);
      when(() => mockAudioService.audioStream)
          .thenAnswer((_) => const Stream.empty());

      final first = controller.startRecording();
      final second = controller.startRecording();
      captureStarted.complete();
      await Future.wait([first, second]);

      final starts = verify(
        () => mockAudioService.startRecording(
          deviceId: any(named: 'deviceId'),
          deviceLabel: any(named: 'deviceLabel'),
        ),
      );
      expect(starts.callCount, equals(1));
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
      ).thenAnswer((_) => Future.value());
      when(() => mockAudioService.audioStream)
          .thenAnswer((_) => const Stream.empty());

      await controller.startRecording();

      expect(controller.currentText, isEmpty);
    });
  });

  group('Hardware Input Guard', () {
    test('startRecording blocks for each non-canRecord status', () async {
      final nonRecordableStatuses = [
        AudioInputStatus.noDevice,
        AudioInputStatus.permissionDenied,
      ];

      for (final status in nonRecordableStatuses) {
        when(() => mockAudioService.inputStatus).thenReturn(status);
        // The pre-refusal re-check confirms the degraded status.
        when(
          () => mockAudioService.evaluateInputStatus(
            targetDeviceId: any(named: 'targetDeviceId'),
          ),
        ).thenAnswer((_) async => status);
        String? emittedError;
        final sub = controller.onError.listen((e) => emittedError = e);

        await controller.startRecording();
        // The refusal now follows an async re-check; let the broadcast
        // stream deliver before asserting and cancelling the listener.
        await Future<void>.delayed(Duration.zero);

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

    test('re-checks a stale degraded status before refusing', () async {
      // Status went stale while the mic was unplugged; it is back now.
      when(() => mockAudioService.inputStatus)
          .thenReturn(AudioInputStatus.noDevice);
      when(
        () => mockAudioService.evaluateInputStatus(
          targetDeviceId: any(named: 'targetDeviceId'),
        ),
      ).thenAnswer((_) async => AudioInputStatus.available);
      when(
        () => mockAudioService.startRecording(
          deviceId: any(named: 'deviceId'),
          deviceLabel: any(named: 'deviceLabel'),
        ),
      ).thenAnswer((_) => Future.value());
      when(() => mockAudioService.audioStream)
          .thenAnswer((_) => const Stream.empty());

      await controller.startRecording();

      final startCall = verify(
        () => mockAudioService.startRecording(
          deviceId: any(named: 'deviceId'),
          deviceLabel: any(named: 'deviceLabel'),
        ),
      );
      expect(startCall.callCount, equals(1));
    });

    test('missing saved microphone records from the system default', () async {
      when(() => mockSettingsService.microphoneId).thenReturn('stale-id');
      when(() => mockSettingsService.microphoneLabel).thenReturn('Old Mic');
      when(() => mockAudioService.inputStatus)
          .thenReturn(AudioInputStatus.selectedUnavailable);
      when(
        () => mockAudioService.startRecording(
          deviceId: any(named: 'deviceId'),
          deviceLabel: any(named: 'deviceLabel'),
        ),
      ).thenAnswer((_) => Future.value());
      when(() => mockAudioService.audioStream)
          .thenAnswer((_) => const Stream.empty());

      await controller.startRecording();

      final defaultDeviceCall = verify(
        () =>
            mockAudioService.startRecording(deviceId: null, deviceLabel: null),
      );
      expect(defaultDeviceCall.callCount, equals(1));
    });

    test('an OS device change re-evaluates hardware status', () async {
      when(() => mockSettingsService.microphoneId).thenReturn('mic-1');
      clearInteractions(mockAudioService);

      deviceChangeController.add(null);
      await Future<void>.delayed(Duration.zero);

      final recheck = verify(
        () => mockAudioService.evaluateInputStatus(targetDeviceId: 'mic-1'),
      );
      expect(recheck.callCount, equals(1));
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
        when(() => mockAudioService.inputStatus)
            .thenReturn(AudioInputStatus.available);
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
      when(() => mockSettingsService.transcriptionSource)
          .thenReturn(TranscriptionSource.groq);
    });

    test(
      'raw profile bypasses transform service and pastes raw text directly',
      () async {
        when(() => mockSettingsService.dictationProfile)
            .thenReturn(DictationProfile.raw);

        await endServerDictation();
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
        when(() => mockSettingsService.dictationProfile)
            .thenReturn(DictationProfile.clean);
        when(
          () => mockTransformService.transform(
            'um raw transcription with fillers you know',
            DictationProfile.clean,
          ),
        ).thenAnswer((_) async => 'Clean transcription without fillers.');

        await endServerDictation();
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
      'a failed polish fails open to raw text and emits error stream',
      () async {
        when(() => mockSettingsService.dictationProfile)
            .thenReturn(DictationProfile.clean);
        when(() => mockTransformService.transform(any(), any())).thenThrow(
          const CloudError(
            service: 'Groq',
            type: CloudErrorType.rateLimited,
            message: 'Rate limit hit',
          ),
        );

        String? emittedError;
        final sub = controller.onError.listen((e) => emittedError = e);

        await endServerDictation();
        mockWsMessageController.add({
          'event': 'transcription',
          'text': 'Raw text fallback.',
        });

        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Fails open: pastes raw text
        verify(() => mockAutomationService.runAutomation('Raw text fallback.'))
            .called(1);
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
        when(() => mockSettingsService.dictationProfile)
            .thenReturn(DictationProfile.clean);

        final completer = Completer<String>();
        when(() => mockTransformService.transform(any(), any()))
            .thenAnswer((_) => completer.future);

        await endServerDictation();
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

    test('a single-passage style pastes its polish on one line', () async {
      when(() => mockSettingsService.dictationProfile)
          .thenReturn(DictationProfile.clean);
      when(() => mockTransformService.transform(any(), any()))
          .thenAnswer((_) async => 'Sure thing.\n\n  echo pwned\n');

      await endServerDictation();
      mockWsMessageController.add({'event': 'transcription', 'text': 'sure'});
      await pumpEventQueue();

      verify(
        () => mockAutomationService.runAutomation('Sure thing. echo pwned'),
      ).called(1);
      expect(controller.currentText, 'Sure thing. echo pwned');
    });

    test('Pro keeps the paragraphs its polish writes', () async {
      const email = 'Hi Sam,\n\nThanks for the notes.';
      when(() => mockSettingsService.dictationProfile)
          .thenReturn(DictationProfile.professional);
      when(() => mockTransformService.transform(any(), any()))
          .thenAnswer((_) async => email);

      await endServerDictation();
      mockWsMessageController.add({'event': 'transcription', 'text': 'hi'});
      await pumpEventQueue();

      final pasted = verify(() => mockAutomationService.runAutomation(email));
      expect(pasted.callCount, 1);
    });

    test('isSessionActive reflects recording state transition', () {
      // A recorder that stops on its own hands its capture to the cloud.
      when(() => mockCloudService.finalizeAndTranscribe())
          .thenAnswer((_) => Future.value(''));
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
      when(() => mockSettingsService.dictationProfile)
          .thenReturn(DictationProfile.clean);
      when(() => mockTransformService.transform(any(), any()))
          .thenAnswer((_) => completer.future);

      await endServerDictation();
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

  group('Server error messages', () {
    test('NO_AUDIO is recognized by error_code', () async {
      // Regression: the check compared the numeric `code` to 'NO_AUDIO', so
      // the microphone hint never showed.
      final errors = <String>[];
      final sub = controller.onError.listen(errors.add);

      mockWsMessageController.add({
        'event': 'error',
        'code': 422,
        'error_code': 'NO_AUDIO',
        'message': 'No audio data received',
      });
      await Future<void>.delayed(Duration.zero);

      expect(errors, ['No audio detected. Please check your microphone.']);
      await sub.cancel();
    });

    test('other server errors surface their message', () async {
      final errors = <String>[];
      final sub = controller.onError.listen(errors.add);

      mockWsMessageController.add({
        'event': 'error',
        'error_code': 'TRANSCRIPTION_FAILED',
        'message': 'Transcription failed',
      });
      await Future<void>.delayed(Duration.zero);

      expect(errors, ['Server error: Transcription failed']);
      await sub.cancel();
    });
  });

  group('Server transcripts', () {
    test('a transcript the app did not ask for is never pasted', () async {
      mockWsMessageController.add({
        'event': 'transcription',
        'text': 'unsolicited text',
      });
      await pumpEventQueue();

      verifyNever(() => mockAutomationService.runAutomation(any()));
      expect(controller.currentText, isEmpty);
    });

    test('waiting for the transcript reads as transcribing', () async {
      await endServerDictation();

      expect(controller.isTranscribing, isTrue);
      expect(controller.isSessionActive, isTrue);
    });

    test('the transcript is pasted as plain text on one line', () async {
      await endServerDictation();
      mockWsMessageController.add({
        'event': 'transcription',
        'text': 'Hello\r\nwhoami\u001b[31m\u0007 ',
      });
      await pumpEventQueue();

      verify(() => mockAutomationService.runAutomation('Hello whoami'))
          .called(1);
      expect(controller.isTranscribing, isFalse);
    });

    test('a second transcript for one dictation is ignored', () async {
      await endServerDictation();
      mockWsMessageController
        ..add({'event': 'transcription', 'text': 'first'})
        ..add({'event': 'transcription', 'text': 'second'});
      await pumpEventQueue();

      verify(() => mockAutomationService.runAutomation(any())).called(1);
      expect(controller.currentText, 'first');
    });

    test('a transcript that is not text is refused', () async {
      final errors = <String>[];
      final sub = controller.onError.listen(errors.add);
      await endServerDictation();

      mockWsMessageController.add({'event': 'transcription', 'text': 42});
      await pumpEventQueue();

      verifyNever(() => mockAutomationService.runAutomation(any()));
      expect(errors, ['Your server sent a reply the app can’t read.']);
      await sub.cancel();
    });

    test('a server error ends the wait and is shown short and plain', () async {
      const longTail = 300;
      const shownAtMost = 200;
      final errors = <String>[];
      final sub = controller.onError.listen(errors.add);
      await endServerDictation();

      mockWsMessageController.add({
        'event': 'error',
        'error_code': 'TRANSCRIPTION_FAILED',
        'message': 'Bad\nthing\u001b[2J ${'x' * longTail}',
      });
      await pumpEventQueue();

      expect(controller.isTranscribing, isFalse);
      expect(errors.single, startsWith('Server error: Bad thing x'));
      expect(errors.single, endsWith('…'));
      expect(errors.single.length, lessThan(shownAtMost));
      await sub.cancel();
    });

    test('an end signal with no session says the dictation is lost', () async {
      final errors = <String>[];
      final sub = controller.onError.listen(errors.add);
      when(() => mockWsService.sendEndSignal()).thenReturn(false);

      await endServerDictation();

      expect(controller.isTranscribing, isFalse);
      expect(errors.single, contains('wasn’t transcribed'));
      await sub.cancel();
    });

    test('losing the connection mid-dictation stops and says so', () async {
      final errors = <String>[];
      final sub = controller.onError.listen(errors.add);
      when(() => mockAudioService.stopRecording()).thenAnswer((_) async {
        when(() => mockAudioService.isRecording).thenReturn(false);
        audioStateListener();
      });
      when(() => mockAudioService.isRecording).thenReturn(true);
      audioStateListener();

      wsStatusController.add(ConnectionStatus.disconnected);
      await pumpEventQueue();

      verify(() => mockAudioService.stopRecording()).called(1);
      verifyNever(() => mockWsService.sendEndSignal());
      expect(controller.isRecording, isFalse);
      expect(errors.single, contains('wasn’t transcribed'));
      await sub.cancel();
    });

    test('losing the connection while waiting ends the wait', () async {
      final errors = <String>[];
      final sub = controller.onError.listen(errors.add);
      await endServerDictation();

      wsStatusController.add(ConnectionStatus.disconnected);
      await pumpEventQueue();
      mockWsMessageController.add({'event': 'transcription', 'text': 'late'});
      await pumpEventQueue();

      expect(controller.isTranscribing, isFalse);
      expect(errors, hasLength(1));
      verifyNever(() => mockAutomationService.runAutomation(any()));
      await sub.cancel();
    });

    test('an untrusted server is named as the reason', () async {
      final errors = <String>[];
      final sub = controller.onError.listen(errors.add);
      when(() => mockWsService.serverProblem)
          .thenReturn(ServerProblem.untrusted);
      when(() => mockWsService.sendEndSignal()).thenReturn(false);

      await endServerDictation();

      expect(errors.single, contains('Trust this server'));
      await sub.cancel();
    });
  });

  group('Cloud dictation', () {
    late StreamController<Uint8List> audio;
    late List<String> errors;
    late StreamSubscription<String> errorSub;

    /// A cloud [source] that is ready (or not, for [problem]), a microphone
    /// that streams [audio], and every error the controller reports in
    /// [errors].
    void useCloud(TranscriptionSource source, {String? problem}) {
      audio = StreamController<Uint8List>.broadcast();
      addTearDown(audio.close);
      errors = [];
      errorSub = controller.onError.listen(errors.add);
      addTearDown(errorSub.cancel);
      when(() => mockSettingsService.transcriptionSource).thenReturn(source);
      when(() => mockCloudService.setupProblem).thenReturn(problem);
      when(() => mockCloudService.begin()).thenReturn(null);
      when(() => mockCloudService.clearBuffer()).thenReturn(null);
      when(() => mockCloudService.bufferAudioChunk(any())).thenReturn(true);
      when(
        () => mockAudioService.startRecording(
          deviceId: any(named: 'deviceId'),
          deviceLabel: any(named: 'deviceLabel'),
        ),
      ).thenAnswer((_) async {
        when(() => mockAudioService.isRecording).thenReturn(true);
        audioStateListener();
      });
      when(() => mockAudioService.stopRecording()).thenAnswer((_) async {
        when(() => mockAudioService.isRecording).thenReturn(false);
      });
      when(() => mockAudioService.audioStream).thenAnswer((_) => audio.stream);
    }

    setUpAll(() => registerFallbackValue(Uint8List(0)));

    test('a source that isn’t ready says why and never records', () async {
      useCloud(
        TranscriptionSource.openRouter,
        problem: 'Add your OpenRouter API key in Account.',
      );

      await controller.startRecording();
      await pumpEventQueue();

      expect(errors, ['Add your OpenRouter API key in Account.']);
      verifyNever(
        () => mockAudioService.startRecording(
          deviceId: any(named: 'deviceId'),
          deviceLabel: any(named: 'deviceLabel'),
        ),
      );
      verifyNever(() => mockCloudService.begin());
    });

    test('the hotkey can’t record with a model known to fail', () async {
      useCloud(
        TranscriptionSource.openRouter,
        problem:
            'OpenRouter stopped serving your model. Choose another in Account.',
      );

      await controller.toggleRecording();
      await pumpEventQueue();

      expect(errors, [
        'OpenRouter stopped serving your model. Choose another in Account.',
      ]);
      expect(controller.isRecording, isFalse);
      verifyNever(() => mockCloudService.begin());
    });

    test('Groq needs no model choice', () async {
      useCloud(TranscriptionSource.groq);

      await controller.startRecording();
      await pumpEventQueue();

      expect(errors, isEmpty);
      expect(verify(() => mockCloudService.begin()).callCount, 1);
    });

    test(
      'the connection is warmed before audio flows, not the server',
      () async {
        useCloud(TranscriptionSource.openRouter);
        when(() => mockSettingsService.openRouterModel)
            .thenReturn('microsoft/mai-transcribe-2');

        await controller.startRecording();
        final chunk = Uint8List.fromList([1, 2, 3, 4]);
        audio.add(chunk);
        await pumpEventQueue();

        verifyInOrder([
          () => mockCloudService.begin(),
          () => mockCloudService.bufferAudioChunk(chunk),
        ]);
        verifyNever(() => mockWsService.ensureConnected());
        verifyNever(() => mockWsService.sendAudioChunk(any()));
        expect(controller.isRecording, isTrue);
      },
    );

    test(
      'a full buffer stops the recording and transcribes what it has',
      () async {
        useCloud(TranscriptionSource.groq);
        when(() => mockCloudService.bufferAudioChunk(any())).thenReturn(false);
        when(() => mockCloudService.finalizeAndTranscribe())
            .thenAnswer((_) async => 'the captured part');

        await controller.startRecording();
        audio.add(Uint8List(1));
        await pumpEventQueue();

        expect(errors, [
          'Max clip length reached (~12 min). Transcribing captured audio.',
        ]);
        expect(verify(() => mockAudioService.stopRecording()).callCount, 1);
        expect(
          verify(() => mockCloudService.finalizeAndTranscribe()).callCount,
          1,
        );
        expect(
          verify(() => mockAutomationService.runAutomation('the captured part'))
              .callCount,
          1,
        );
      },
    );

    test('stopping uploads the clip and pastes its text', () async {
      useCloud(TranscriptionSource.groq);
      when(() => mockCloudService.finalizeAndTranscribe())
          .thenAnswer((_) async => 'Send the invoice.');

      await controller.startRecording();
      await controller.stopRecording();
      await pumpEventQueue();

      expect(
        verify(() => mockAutomationService.runAutomation('Send the invoice.'))
            .callCount,
        1,
      );
      verifyNever(() => mockWsService.sendEndSignal());
      expect(controller.currentText, 'Send the invoice.');
      expect(controller.isTranscribing, isFalse);
    });

    test(
      'a failed upload reports the service’s message and pastes nothing',
      () async {
        useCloud(TranscriptionSource.openRouter);
        when(() => mockSettingsService.openRouterModel)
            .thenReturn('microsoft/mai-transcribe-2');
        when(() => mockCloudService.finalizeAndTranscribe()).thenThrow(
          const CloudError(
            service: 'OpenRouter',
            type: CloudErrorType.insufficientCredits,
            message: 'Insufficient credits',
          ),
        );

        await controller.startRecording();
        await controller.stopRecording();
        await pumpEventQueue();

        expect(errors, [
          'Your OpenRouter credits ran out. Add credits to keep dictating.',
        ]);
        verifyNever(() => mockAutomationService.runAutomation(any()));
        expect(controller.isTranscribing, isFalse);
      },
    );

    test('while it uploads, a new recording can’t start', () async {
      useCloud(TranscriptionSource.groq);
      final upload = Completer<String>();
      when(() => mockCloudService.finalizeAndTranscribe())
          .thenAnswer((_) => upload.future);

      await controller.startRecording();
      await controller.stopRecording();
      await pumpEventQueue();
      expect(controller.isTranscribing, isTrue);
      await controller.startRecording();

      expect(verify(() => mockCloudService.begin()).callCount, 1);
      upload.complete('');
      await pumpEventQueue();
      expect(controller.isTranscribing, isFalse);
    });

    test(
      'a dropped server connection leaves a cloud dictation alone',
      () async {
        useCloud(TranscriptionSource.groq);

        await controller.startRecording();
        wsStatusController.add(ConnectionStatus.disconnected);
        await pumpEventQueue();

        expect(errors, isEmpty);
        expect(controller.isRecording, isTrue);
      },
    );

    test('incognito clears audio held for an upload', () async {
      when(() => mockCloudService.clearBuffer()).thenReturn(null);

      await controller.enableIncognitoMode();

      expect(verify(() => mockCloudService.clearBuffer()).callCount, 1);
    });
  });
}
