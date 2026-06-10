// ignore_for_file: no-magic-number, prefer-moving-to-variable
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

    test('returns selectedUnavailable when the target device is missing',
        () async {
      when(() => mockRecorder.listInputDevices()).thenAnswer(
        (_) async => const [InputDevice(id: 'dev-1', label: 'Mic 1')],
      );
      final audioService = AudioService(audioRecorder: mockRecorder);

      final status = await audioService.evaluateInputStatus(
        targetDeviceId: 'dev-2',
      );
      expect(status, equals(AudioInputStatus.selectedUnavailable));
    });

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

    test('returns available when devices exist and no target is specified',
        () async {
      when(() => mockRecorder.listInputDevices()).thenAnswer(
        (_) async => const [InputDevice(id: 'dev-1', label: 'Mic 1')],
      );
      final audioService = AudioService(audioRecorder: mockRecorder);

      final status = await audioService.evaluateInputStatus();
      expect(status, equals(AudioInputStatus.available));
    });

    test('treats enumeration failure as noDevice', () async {
      when(() => mockRecorder.listInputDevices()).thenThrow(Exception('IO'));
      final audioService = AudioService(audioRecorder: mockRecorder);

      final status = await audioService.evaluateInputStatus();
      expect(status, equals(AudioInputStatus.noDevice));
    });

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
    test('sets permissionDenied and throws when permission is refused',
        () async {
      when(() => mockRecorder.hasPermission()).thenAnswer((_) async => false);
      final audioService = AudioService(audioRecorder: mockRecorder);

      await expectLater(audioService.startRecording(), throwsException);
      expect(
        audioService.inputStatus,
        equals(AudioInputStatus.permissionDenied),
      );
    });

    test('sets noDevice and rethrows when the stream fails to start', () async {
      when(() => mockRecorder.hasPermission()).thenAnswer((_) async => true);
      when(
        () => mockRecorder.startStream(any()),
      ).thenThrow(Exception('No audio recording device'));
      final audioService = AudioService(audioRecorder: mockRecorder);

      await expectLater(audioService.startRecording(), throwsException);
      expect(audioService.inputStatus, equals(AudioInputStatus.noDevice));
    });
  });
}
