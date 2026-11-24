import 'package:flutter_client/logic/models/model_selection_problem.dart';
import 'package:flutter_client/logic/models/transcription_source.dart';
import 'package:flutter_client/services/hardware/audio_input_status.dart';
import 'package:flutter_client/services/transport/server_problem.dart';
import 'package:flutter_client/services/utility/update_service.dart';

/// Maps [HomeSignals] onto a [HomeStatus]. Order matters: an active session
/// wins over every setup problem, and a missing microphone wins over account
/// problems because it is the one the user can fix fastest.
abstract final class HomeStatusMapper {
  static HomeStatus map(HomeSignals s) {
    final badge = _badge(s);

    if (s.isRecording) {
      return s.showSilenceWarning
          ? HomeStatus(
              phase: HomePhase.listening,
              cue: 'can’t hear you',
              tone: CueTone.alert,
              badge: badge,
            )
          : HomeStatus(
              phase: HomePhase.listening,
              cue: 'listening',
              tone: CueTone.live,
              badge: badge,
            );
    }

    if (s.isTranscribing) {
      return HomeStatus(
        phase: HomePhase.working,
        cue: s.isPolishing ? 'polishing · ${s.styleLabel}' : 'transcribing',
        tone: CueTone.muted,
        badge: badge,
      );
    }

    final blocked = _microphoneProblem(s, badge) ?? _accountProblem(s, badge);
    if (blocked != null) return blocked;

    return HomeStatus(
      phase: HomePhase.ready,
      cue: s.inputStatus.usesDefaultDevice
          ? 'ready · default microphone'
          : 'ready',
      tone: CueTone.muted,
      badge: badge,
    );
  }

  static HomeStatus? _microphoneProblem(HomeSignals s, AccountBadge badge) {
    return switch (s.inputStatus) {
      AudioInputStatus.noDevice => HomeStatus(
        phase: HomePhase.blocked,
        cue: 'no microphone',
        tone: CueTone.alert,
        badge: badge,
        headline: 'Plug one in, or choose another.',
        fix: HomeFix.openSettings,
        fixLabel: 'Choose',
      ),
      AudioInputStatus.permissionDenied => HomeStatus(
        phase: HomePhase.blocked,
        cue: 'microphone blocked',
        tone: CueTone.alert,
        badge: badge,
        headline: 'Allow microphone access in Windows privacy settings.',
        fix: HomeFix.retryMicrophone,
        fixLabel: 'Try again',
      ),
      AudioInputStatus.available ||
      AudioInputStatus.unknown ||
      AudioInputStatus.selectedUnavailable => null,
    };
  }

  static HomeStatus? _accountProblem(HomeSignals s, AccountBadge badge) {
    if (s.source.isCloud) return _cloudProblem(s, badge);

    if (s.isBanned) {
      return HomeStatus(
        phase: HomePhase.blocked,
        cue: 'paused',
        tone: CueTone.alert,
        badge: badge,
      );
    }

    if (s.updateStatus == UpdateStatus.required) {
      return HomeStatus(
        phase: HomePhase.blocked,
        cue: 'update needed',
        tone: CueTone.alert,
        badge: badge,
        headline: 'This version is too old for your server.',
        fix: HomeFix.openAccount,
        fixLabel: 'Update',
      );
    }

    if (s.handshakeFailed) {
      return HomeStatus(
        phase: HomePhase.blocked,
        cue: 'can’t connect',
        tone: CueTone.alert,
        badge: badge,
        headline: 'Your server didn’t accept the sign-in.',
        fix: HomeFix.openAccount,
        fixLabel: 'Check account',
      );
    }

    if (!s.isSignedIn) {
      return HomeStatus(
        phase: HomePhase.blocked,
        cue: 'not signed in',
        tone: CueTone.alert,
        badge: badge,
        headline: 'Sign in to start dictating.',
        fix: HomeFix.openAccount,
        fixLabel: 'Sign in',
      );
    }

    return _serverProblem(s, badge);
  }

  /// A cloud source needs a key and, on OpenRouter, a model it still serves.
  static HomeStatus? _cloudProblem(HomeSignals s, AccountBadge badge) {
    if (!s.hasCloudKey) {
      return HomeStatus(
        phase: HomePhase.blocked,
        cue: 'not set up',
        tone: CueTone.alert,
        badge: badge,
        headline: 'Add your ${s.source.label} API key to start.',
        fix: HomeFix.openAccount,
        fixLabel: 'Add key',
      );
    }

    // The first model is chosen as soon as the list arrives.
    final loading = _isFirstLoad(s);
    final failed = s.modelProblem == ModelSelectionProblem.notChosen
        ? s.modelListError
        : null;
    final words = _modelWords(s.modelProblem, loading: loading, failed: failed);
    if (words == null) return null;
    final (cue, headline) = words;

    return HomeStatus(
      phase: HomePhase.blocked,
      cue: cue,
      tone: loading ? CueTone.muted : CueTone.alert,
      badge: badge,
      headline: headline,
      fix: HomeFix.chooseModel,
      fixLabel: _modelFixLabel(loading: loading, failed: failed),
    );
  }

  /// Nothing to press while the list loads; opening the picker also retries
  /// a list that failed to load.
  static String? _modelFixLabel({
    required bool loading,
    required String? failed,
  }) {
    if (loading) return null;

    return failed == null ? 'Choose' : 'Try again';
  }

  /// No model yet because the first list is still on its way: not a
  /// problem, only a wait.
  static bool _isFirstLoad(HomeSignals s) =>
      s.modelProblem == ModelSelectionProblem.notChosen && s.isLoadingModels;

  /// The cue and headline for an unusable OpenRouter model.
  static (String, String)? _modelWords(
    ModelSelectionProblem problem, {
    required bool loading,
    required String? failed,
  }) => switch (problem) {
    ModelSelectionProblem.none => null,
    ModelSelectionProblem.notChosen when loading => (
      'loading models',
      'Fetching OpenRouter’s models.',
    ),
    ModelSelectionProblem.notChosen when failed != null => (
      'can’t load models',
      failed,
    ),
    ModelSelectionProblem.notChosen => (
      'no model',
      'Choose an OpenRouter model to start.',
    ),
    ModelSelectionProblem.retired => (
      'model retired',
      'OpenRouter stopped serving your model. Choose another.',
    ),
    ModelSelectionProblem.retainsData => (
      'model keeps data',
      'Zero data retention is on, and your model keeps data. '
          'Choose another.',
    ),
  };

  /// Signed in, but the last attempt never reached the server. An idle
  /// disconnect is not a problem: dictation reconnects on demand.
  static HomeStatus? _serverProblem(HomeSignals s, AccountBadge badge) {
    if (s.serverProblem == ServerProblem.none) return null;
    // A retry or a just-trusted server: hold the problem's place quietly
    // until the attempt settles, rather than flash "ready".
    if (s.isConnecting) {
      return HomeStatus(
        phase: HomePhase.blocked,
        cue: 'connecting',
        tone: CueTone.muted,
        badge: badge,
        headline: 'Connecting to your server.',
        // Keeps the server glyph on the cue; no label, so no button.
        fix: HomeFix.retryServer,
      );
    }

    return switch (s.serverProblem) {
      ServerProblem.none => null,
      ServerProblem.untrusted => HomeStatus(
        phase: HomePhase.blocked,
        cue: 'new server',
        tone: CueTone.alert,
        badge: badge,
        headline:
            'Send your sign-in to ${s.serverHost}? Only trust a server you '
            'run or know.',
        fix: HomeFix.trustServer,
        fixLabel: 'Trust server',
      ),
      ServerProblem.unreachable => HomeStatus(
        phase: HomePhase.blocked,
        cue: 'server offline',
        tone: CueTone.alert,
        badge: badge,
        headline: 'Your server isn’t answering. Check that it’s running.',
        fix: HomeFix.retryServer,
        fixLabel: 'Try again',
      ),
      ServerProblem.insecure => HomeStatus(
        phase: HomePhase.blocked,
        cue: 'address not allowed',
        tone: CueTone.alert,
        badge: badge,
        headline: 'Servers outside your network need a wss:// address.',
        fix: HomeFix.openAccount,
        fixLabel: 'Check address',
      ),
    };
  }

  static AccountBadge _badge(HomeSignals s) {
    final accountBroken = s.source.isCloud
        ? !s.hasCloudKey ||
              (s.modelProblem != ModelSelectionProblem.none && !_isFirstLoad(s))
        : (s.handshakeFailed ||
              s.isBanned ||
              !s.isSignedIn ||
              s.serverProblem == ServerProblem.insecure);
    if (accountBroken || s.updateStatus == UpdateStatus.required) {
      return AccountBadge.attention;
    }

    return s.updateStatus == UpdateStatus.advisory
        ? AccountBadge.update
        : AccountBadge.none;
  }
}

/// What the home stage is doing.
enum HomePhase { ready, listening, working, blocked }

/// How a caption cue is coloured.
enum CueTone { muted, live, alert }

/// The single action that resolves a blocked state.
enum HomeFix {
  none,
  openAccount,

  /// OpenRouter's model picker.
  chooseModel,
  openSettings,
  retryMicrophone,
  retryServer,
  trustServer,
}

/// The dot on the account indicator.
enum AccountBadge { none, update, attention }

/// Everything the service layer says that the home screen depends on.
class HomeSignals {
  const HomeSignals({
    required this.source,
    required this.hasCloudKey,
    this.modelProblem = ModelSelectionProblem.none,
    this.isLoadingModels = false,
    this.modelListError,
    required this.isSignedIn,
    required this.handshakeFailed,
    required this.isBanned,
    required this.serverProblem,
    required this.serverHost,
    required this.isConnecting,
    required this.updateStatus,
    required this.inputStatus,
    required this.isRecording,
    required this.isTranscribing,
    required this.isPolishing,
    required this.showSilenceWarning,
    required this.styleLabel,
  });

  final TranscriptionSource source;

  /// Cloud source: its API key is saved.
  final bool hasCloudKey;

  /// OpenRouter: whether the chosen model can be used.
  final ModelSelectionProblem modelProblem;

  /// OpenRouter: the model list is being fetched.
  final bool isLoadingModels;

  /// OpenRouter: why the last model list failed to load, as the user should
  /// read it; null when it loaded (or hasn't been tried).
  final String? modelListError;

  /// Self-hosted mode: holds a sign-in or API key. The connection itself
  /// opens on demand and closes when idle.
  final bool isSignedIn;
  final bool handshakeFailed;
  final bool isBanned;

  /// Self-hosted mode: why the last attempt never reached the server.
  final ServerProblem serverProblem;

  /// Self-hosted mode: the configured server's host, named when asking
  /// whether to trust it.
  final String serverHost;

  /// Self-hosted mode: an attempt to reach the server is under way.
  final bool isConnecting;
  final UpdateStatus updateStatus;
  final AudioInputStatus inputStatus;
  final bool isRecording;
  final bool isTranscribing;

  /// Transcribing finished and an output style is rewriting the text.
  final bool isPolishing;
  final bool showSilenceWarning;

  /// Active output style, e.g. "Clean".
  final String styleLabel;
}

/// What the home screen shows, decided in one place.
class HomeStatus {
  const HomeStatus({
    required this.phase,
    required this.cue,
    required this.tone,
    required this.badge,
    this.headline,
    this.fix = HomeFix.none,
    this.fixLabel,
  });

  final HomePhase phase;

  /// Caption cue text without brackets, e.g. "ready", "no microphone".
  final String cue;
  final CueTone tone;
  final AccountBadge badge;

  /// One plain-language sentence for blocked states.
  final String? headline;
  final HomeFix fix;
  final String? fixLabel;

  bool get canRecord => phase == HomePhase.ready;
}
