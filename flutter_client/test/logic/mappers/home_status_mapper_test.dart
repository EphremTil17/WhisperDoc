import 'package:flutter_client/logic/mappers/home_status_mapper.dart';
import 'package:flutter_client/logic/models/model_selection_problem.dart';
import 'package:flutter_client/logic/models/transcription_source.dart';
import 'package:flutter_client/services/hardware/audio_input_status.dart';
import 'package:flutter_client/services/transport/server_problem.dart';
import 'package:flutter_client/services/utility/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  HomeSignals signals({
    TranscriptionSource source = TranscriptionSource.groq,
    bool hasCloudKey = true,
    ModelSelectionProblem modelProblem = ModelSelectionProblem.none,
    bool isLoadingModels = false,
    String? modelListError,
    bool isSignedIn = true,
    bool handshakeFailed = false,
    bool isBanned = false,
    ServerProblem serverProblem = ServerProblem.none,
    String serverHost = 'whisper.example.com',
    bool isConnecting = false,
    UpdateStatus updateStatus = UpdateStatus.upToDate,
    AudioInputStatus inputStatus = AudioInputStatus.available,
    bool isRecording = false,
    bool isTranscribing = false,
    bool isPolishing = false,
    bool showSilenceWarning = false,
  }) => HomeSignals(
    source: source,
    hasCloudKey: hasCloudKey,
    modelProblem: modelProblem,
    isLoadingModels: isLoadingModels,
    modelListError: modelListError,
    isSignedIn: isSignedIn,
    handshakeFailed: handshakeFailed,
    isBanned: isBanned,
    serverProblem: serverProblem,
    serverHost: serverHost,
    isConnecting: isConnecting,
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
        signals(isRecording: true, hasCloudKey: false),
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
        signals(inputStatus: AudioInputStatus.noDevice, hasCloudKey: false),
      );

      expect(status.cue, 'no microphone');
      expect(status.badge, AccountBadge.attention);
    });

    test('a cloud source without its key names the service to add it for', () {
      for (final source in [
        TranscriptionSource.groq,
        TranscriptionSource.openRouter,
      ]) {
        final status = HomeStatusMapper.map(
          signals(source: source, hasCloudKey: false),
        );

        expect(status.phase, HomePhase.blocked);
        expect(status.cue, 'not set up');
        expect(status.headline, 'Add your ${source.label} API key to start.');
        expect(status.fix, HomeFix.openAccount);
        expect(status.fixLabel, 'Add key');
        expect(status.badge, AccountBadge.attention);
      }
    });

    test('OpenRouter blocks on a model it can’t use, with a way to choose', () {
      const cases = {
        ModelSelectionProblem.notChosen: (
          'no model',
          'Choose an OpenRouter model to start.',
        ),
        ModelSelectionProblem.retired: (
          'model retired',
          'OpenRouter stopped serving your model. Choose another.',
        ),
        ModelSelectionProblem.retainsData: (
          'model keeps data',
          'Zero data retention is on, and your model keeps data. '
              'Choose another.',
        ),
      };
      for (final MapEntry(key: problem, value: (cue, headline))
          in cases.entries) {
        final status = HomeStatusMapper.map(
          signals(
            source: TranscriptionSource.openRouter,
            modelProblem: problem,
          ),
        );

        expect(status.phase, HomePhase.blocked, reason: '$problem');
        expect(status.cue, cue);
        expect(status.headline, headline);
        expect(status.tone, CueTone.alert);
        expect(status.fix, HomeFix.chooseModel);
        expect(status.fixLabel, 'Choose');
        expect(status.badge, AccountBadge.attention);
      }
    });

    test('while the first model list loads it waits quietly, no button', () {
      final status = HomeStatusMapper.map(
        signals(
          source: TranscriptionSource.openRouter,
          modelProblem: ModelSelectionProblem.notChosen,
          isLoadingModels: true,
        ),
      );

      expect(status.phase, HomePhase.blocked);
      expect(status.cue, 'loading models');
      expect(status.tone, CueTone.muted);
      expect(status.fixLabel, isNull);
      expect(status.fix, HomeFix.chooseModel); // its glyph on the cue
      expect(status.canRecord, isFalse);
    });

    test('the first load is a wait, not a fault: no attention dot', () {
      final status = HomeStatusMapper.map(
        signals(
          source: TranscriptionSource.openRouter,
          modelProblem: ModelSelectionProblem.notChosen,
          isLoadingModels: true,
        ),
      );

      expect(status.badge, AccountBadge.none);
    });

    test('a list that failed to load says why and offers to try again', () {
      final status = HomeStatusMapper.map(
        signals(
          source: TranscriptionSource.openRouter,
          modelProblem: ModelSelectionProblem.notChosen,
          modelListError: 'Cannot reach OpenRouter. Check your connection.',
        ),
      );

      expect(status.cue, 'can’t load models');
      expect(
        status.headline,
        'Cannot reach OpenRouter. Check your connection.',
      );
      expect(status.tone, CueTone.alert);
      expect(status.fix, HomeFix.chooseModel);
      expect(status.fixLabel, 'Try again');
      expect(status.badge, AccountBadge.attention);
    });

    test('a usable OpenRouter model is ready, even mid-refresh', () {
      final status = HomeStatusMapper.map(
        signals(source: TranscriptionSource.openRouter, isLoadingModels: true),
      );

      expect(status.phase, HomePhase.ready);
      expect(status.badge, AccountBadge.none);
    });

    test('server problems never block a cloud source', () {
      final status = HomeStatusMapper.map(
        signals(
          source: TranscriptionSource.openRouter,
          isSignedIn: false,
          handshakeFailed: true,
          serverProblem: ServerProblem.unreachable,
        ),
      );

      expect(status.phase, HomePhase.ready);
      expect(status.badge, AccountBadge.none);
    });

    test('self-hosted mode: signed out, failed handshake, required update', () {
      final signedOut = HomeStatusMapper.map(
        signals(source: TranscriptionSource.server, isSignedIn: false),
      );
      final failed = HomeStatusMapper.map(
        signals(source: TranscriptionSource.server, handshakeFailed: true),
      );
      final tooOld = HomeStatusMapper.map(
        signals(
          source: TranscriptionSource.server,
          updateStatus: UpdateStatus.required,
        ),
      );

      expect(signedOut.cue, 'not signed in');
      expect(failed.cue, 'can’t connect');
      expect(tooOld.cue, 'update needed');
      for (final status in [signedOut, failed, tooOld]) {
        expect(status.fix, HomeFix.openAccount);
        expect(status.badge, AccountBadge.attention);
      }
    });

    test('signed in with the server offline says so and offers a retry', () {
      final status = HomeStatusMapper.map(
        signals(
          source: TranscriptionSource.server,
          serverProblem: ServerProblem.unreachable,
        ),
      );

      expect(status.phase, HomePhase.blocked);
      expect(status.cue, 'server offline');
      expect(status.fix, HomeFix.retryServer);
      expect(status.fixLabel, 'Try again');
      expect(status.badge, AccountBadge.none);
    });

    test('a retry under way shows connecting without a button', () {
      final status = HomeStatusMapper.map(
        signals(
          source: TranscriptionSource.server,
          serverProblem: ServerProblem.unreachable,
          isConnecting: true,
        ),
      );

      expect(status.phase, HomePhase.blocked);
      expect(status.cue, 'connecting');
      expect(status.tone, CueTone.muted);
      expect(status.fixLabel, isNull);
    });

    test('a refused address points at the account', () {
      final status = HomeStatusMapper.map(
        signals(
          source: TranscriptionSource.server,
          serverProblem: ServerProblem.insecure,
        ),
      );

      expect(status.cue, 'address not allowed');
      expect(status.fix, HomeFix.openAccount);
      expect(status.badge, AccountBadge.attention);
    });

    test('a server not yet trusted asks, naming it, before any sign-in', () {
      final status = HomeStatusMapper.map(
        signals(
          source: TranscriptionSource.server,
          serverProblem: ServerProblem.untrusted,
        ),
      );

      expect(status.phase, HomePhase.blocked);
      expect(status.cue, 'new server');
      expect(status.headline, contains('whisper.example.com'));
      expect(status.fix, HomeFix.trustServer);
      expect(status.fixLabel, 'Trust server');
      expect(status.canRecord, isFalse);
    });

    test('connecting after trusting shows connecting, not the question', () {
      final status = HomeStatusMapper.map(
        signals(
          source: TranscriptionSource.server,
          serverProblem: ServerProblem.untrusted,
          isConnecting: true,
        ),
      );

      expect(status.cue, 'connecting');
      expect(status.fixLabel, isNull);
    });

    test('signing out wins over an offline server', () {
      final status = HomeStatusMapper.map(
        signals(
          source: TranscriptionSource.server,
          isSignedIn: false,
          serverProblem: ServerProblem.unreachable,
        ),
      );

      expect(status.cue, 'not signed in');
    });

    test('signed in with an idle, closed connection is ready', () {
      final status = HomeStatusMapper.map(
        signals(source: TranscriptionSource.server),
      );

      expect(status.phase, HomePhase.ready);
    });

    test('a banned connection is paused without a fix button', () {
      final status = HomeStatusMapper.map(
        signals(source: TranscriptionSource.server, isBanned: true),
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
