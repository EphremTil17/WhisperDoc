// Test fixtures intentionally use late setup fields and private mock classes.
// ignore_for_file: no-magic-number, prefer-moving-to-variable, prefer-match-file-name, avoid-late-keyword

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:record/record.dart';
import 'package:flutter_client/services/hardware/audio_input_status.dart';
import 'package:flutter_client/services/hardware/audio_service.dart';

class _MockAudioRecorder extends Mock implements AudioRecorder {}

void main() {
  late _MockAudioRecorder mockRecorder;

  setUpAll(() {
    registerFallbackValue(const RecordConfig());
  });

  setUp(() {
    mockRecorder = _MockAudioRecorder();
  });

  group('AudioService input status evaluation', () {
    test('inputStatus defaults to unknown and permits recording', () {
      final audioService = AudioService(audioRecorder: mockRecorder);
      expect(audioService.inputStatus, equals(AudioInputStatus.unknown));
      expect(audioService.inputStatus.canRecord, isTrue);
    });

    test('returns noDevice when no input devices are enumerated', () async {
      when(() => mockRecorder.listInputDevices()).thenAnswer((_) async => []);
      final audioService = AudioService(audioRecorder: mockRecorder);

      final status = await audioService.evaluateInputStatus();
      expect(status, equals(AudioInputStatus.noDevice));
      expect(audioService.inputStatus, equals(AudioInputStatus.noDevice));
    });

    test(
      'returns selectedUnavailable when the target device is missing',
      () async {
        when(() => mockRecorder.listInputDevices()).thenAnswer(
          (_) async => const [InputDevice(id: 'dev-1', label: 'Mic 1')],
        );
        final audioService = AudioService(audioRecorder: mockRecorder);

        final status = await audioService.evaluateInputStatus(
          targetDeviceId: 'dev-2',
        );
        expect(status, equals(AudioInputStatus.selectedUnavailable));
      },
    );

    test('returns available when the target device is present', () async {
      when(() => mockRecorder.listInputDevices()).thenAnswer(
        (_) async => const [InputDevice(id: 'dev-1', label: 'Mic 1')],
      );
      final audioService = AudioService(audioRecorder: mockRecorder);

      final status = await audioService.evaluateInputStatus(
        targetDeviceId: 'dev-1',
      );
      expect(status, equals(AudioInputStatus.available));
    });

    test(
      'returns available when devices exist and no target is specified',
      () async {
        when(() => mockRecorder.listInputDevices()).thenAnswer(
          (_) async => const [InputDevice(id: 'dev-1', label: 'Mic 1')],
        );
        final audioService = AudioService(audioRecorder: mockRecorder);

        final status = await audioService.evaluateInputStatus();
        expect(status, equals(AudioInputStatus.available));
      },
    );

    test(
      'treats enumeration failure as unknown so recording stays possible',
      () async {
        // The Windows plugin fails the whole listing when one endpoint is
        // mid-transition; that is not evidence of a missing microphone.
        when(() => mockRecorder.listInputDevices()).thenThrow(Exception('IO'));
        final audioService = AudioService(audioRecorder: mockRecorder);

        final status = await audioService.evaluateInputStatus();
        expect(status, equals(AudioInputStatus.unknown));
        expect(status.canRecord, isTrue);
      },
    );

    test('notifies once per real status transition', () async {
      final audioService = AudioService(audioRecorder: mockRecorder);
      var notifications = 0;
      audioService.addListener(() => notifications++);

      when(() => mockRecorder.listInputDevices()).thenAnswer((_) async => []);
      final degraded = await audioService.evaluateInputStatus();
      expect(degraded, equals(AudioInputStatus.noDevice));
      expect(notifications, equals(1)); // unknown -> noDevice

      when(() => mockRecorder.listInputDevices()).thenAnswer(
        (_) async => const [InputDevice(id: 'dev-1', label: 'Mic 1')],
      );
      final recovered = await audioService.evaluateInputStatus();
      expect(recovered, equals(AudioInputStatus.available));
      expect(notifications, equals(2)); // noDevice -> available
    });
  });

  group('AudioService startRecording status mutation', () {
    test(
      'sets permissionDenied and throws when permission is refused',
      () async {
        when(() => mockRecorder.hasPermission()).thenAnswer((_) async => false);
        final audioService = AudioService(audioRecorder: mockRecorder);

        await expectLater(audioService.startRecording(), throwsException);
        expect(
          audioService.inputStatus,
          equals(AudioInputStatus.permissionDenied),
        );
      },
    );

    test(
      'sets noDevice and rethrows when the stream fails with no devices',
      () async {
        when(() => mockRecorder.hasPermission()).thenAnswer((_) async => true);
        when(() => mockRecorder.startStream(any()))
            .thenThrow(Exception('No audio recording device'));
        when(() => mockRecorder.listInputDevices()).thenAnswer((_) async => []);
        final audioService = AudioService(audioRecorder: mockRecorder);

        await expectLater(audioService.startRecording(), throwsException);
        expect(audioService.inputStatus, equals(AudioInputStatus.noDevice));
      },
    );

    test(
      'stays recordable when the stream fails but devices are present',
      () async {
        // A busy or transient device must not be reported as missing.
        when(() => mockRecorder.hasPermission()).thenAnswer((_) async => true);
        when(() => mockRecorder.startStream(any()))
            .thenThrow(Exception('Device in use'));
        when(() => mockRecorder.listInputDevices()).thenAnswer(
          (_) async => const [InputDevice(id: 'dev-1', label: 'Mic 1')],
        );
        final audioService = AudioService(audioRecorder: mockRecorder);

        await expectLater(audioService.startRecording(), throwsException);
        expect(audioService.inputStatus, equals(AudioInputStatus.available));
      },
    );
  });

  group('AudioInputStatus policy', () {
    test('a missing saved microphone falls back to the default device', () {
      const status = AudioInputStatus.selectedUnavailable;
      expect(status.canRecord, isTrue);
      expect(status.usesDefaultDevice, isTrue);
      expect(status.bannerMessage, isNotNull);
    });

    test('only selectedUnavailable redirects to the default device', () {
      final redirecting = AudioInputStatus.values.where(
        (s) => s.usesDefaultDevice,
      );
      expect(redirecting, equals([AudioInputStatus.selectedUnavailable]));
    });
  });
}
