import 'package:flutter_client/logic/mappers/home_status_mapper.dart';
import 'package:flutter_client/services/hardware/audio_input_status.dart';
import 'package:flutter_client/services/utility/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  HomeSignals signals({
    bool isGroqMode = true,
    bool hasGroqKey = true,
    bool isSignedIn = true,
    bool handshakeFailed = false,
    bool isBanned = false,
    UpdateStatus updateStatus = UpdateStatus.upToDate,
    AudioInputStatus inputStatus = AudioInputStatus.available,
    bool isRecording = false,
    bool isTranscribing = false,
    bool isPolishing = false,
    bool showSilenceWarning = false,
  }) => HomeSignals(
    isGroqMode: isGroqMode,
    hasGroqKey: hasGroqKey,
    isSignedIn: isSignedIn,
    handshakeFailed: handshakeFailed,
    isBanned: isBanned,
    updateStatus: updateStatus,
    inputStatus: inputStatus,
    isRecording: isRecording,
    isTranscribing: isTranscribing,
    isPolishing: isPolishing,
    showSilenceWarning: showSilenceWarning,
    styleLabel: 'Clean',
  );

  group('HomeStatusMapper', () {
    test('everything fine reads as ready with no badge', () {
      final status = HomeStatusMapper.map(signals());

      expect(status.phase, HomePhase.ready);
      expect(status.cue, 'ready');
      expect(status.canRecord, isTrue);
      expect(status.badge, AccountBadge.none);
    });

    test('a fallback to the default microphone stays ready and says so', () {
      final status = HomeStatusMapper.map(
        signals(inputStatus: AudioInputStatus.selectedUnavailable),
      );

      expect(status.phase, HomePhase.ready);
      expect(status.cue, 'ready · default microphone');
    });

    test('recording is listening, and silence turns the cue into an alert', () {
      final live = HomeStatusMapper.map(signals(isRecording: true));
      final silent = HomeStatusMapper.map(
        signals(isRecording: true, showSilenceWarning: true),
      );

      expect(live.phase, HomePhase.listening);
      expect(live.tone, CueTone.live);
      expect(silent.phase, HomePhase.listening);
      expect(silent.tone, CueTone.alert);
    });

    test('transcribing names the output style while it polishes', () {
      final plain = HomeStatusMapper.map(signals(isTranscribing: true));
      final polishing = HomeStatusMapper.map(
        signals(isTranscribing: true, isPolishing: true),
      );

      expect(plain.cue, 'transcribing');
      expect(polishing.cue, 'polishing · Clean');
      expect(polishing.canRecord, isFalse);
    });

    test('an active session wins over setup problems', () {
      final status = HomeStatusMapper.map(
        signals(isRecording: true, hasGroqKey: false),
      );

      expect(status.phase, HomePhase.listening);
      expect(status.badge, AccountBadge.attention);
    });

    test('no microphone blocks and points at settings', () {
      final status = HomeStatusMapper.map(
        signals(inputStatus: AudioInputStatus.noDevice),
      );

      expect(status.phase, HomePhase.blocked);
      expect(status.fix, HomeFix.openSettings);
      expect(status.canRecord, isFalse);
    });

    test('a blocked microphone offers a retry', () {
      final status = HomeStatusMapper.map(
        signals(inputStatus: AudioInputStatus.permissionDenied),
      );

      expect(status.fix, HomeFix.retryMicrophone);
    });

    test('a microphone problem wins over an account problem', () {
      final status = HomeStatusMapper.map(
        signals(inputStatus: AudioInputStatus.noDevice, hasGroqKey: false),
      );

      expect(status.cue, 'no microphone');
      expect(status.badge, AccountBadge.attention);
    });

    test('Groq mode without a key blocks and points at the account', () {
      final status = HomeStatusMapper.map(signals(hasGroqKey: false));

      expect(status.phase, HomePhase.blocked);
      expect(status.fix, HomeFix.openAccount);
      expect(status.badge, AccountBadge.attention);
    });

    test('self-hosted mode: signed out, failed handshake, required update', () {
      final signedOut = HomeStatusMapper.map(
        signals(isGroqMode: false, isSignedIn: false),
      );
      final failed = HomeStatusMapper.map(
        signals(isGroqMode: false, handshakeFailed: true),
      );
      final tooOld = HomeStatusMapper.map(
        signals(isGroqMode: false, updateStatus: UpdateStatus.required),
      );

      expect(signedOut.cue, 'not signed in');
      expect(failed.cue, 'can’t connect');
      expect(tooOld.cue, 'update needed');
      for (final status in [signedOut, failed, tooOld]) {
        expect(status.fix, HomeFix.openAccount);
        expect(status.badge, AccountBadge.attention);
      }
    });

    test('a banned connection is paused without a fix button', () {
      final status = HomeStatusMapper.map(
        signals(isGroqMode: false, isBanned: true),
      );

      expect(status.phase, HomePhase.blocked);
      expect(status.fix, HomeFix.none);
    });

    test('an optional update only adds the amber badge', () {
      final status = HomeStatusMapper.map(
        signals(updateStatus: UpdateStatus.advisory),
      );

      expect(status.phase, HomePhase.ready);
      expect(status.badge, AccountBadge.update);
    });
  });
}
