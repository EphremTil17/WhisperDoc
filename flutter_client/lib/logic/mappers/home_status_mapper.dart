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
    if (s.isGroqMode) {
      return s.hasGroqKey
          ? null
          : HomeStatus(
              phase: HomePhase.blocked,
              cue: 'not set up',
              tone: CueTone.alert,
              badge: badge,
              headline: 'Add your Groq API key to start.',
              fix: HomeFix.openAccount,
              fixLabel: 'Add key',
            );
    }

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
    final accountBroken = s.isGroqMode
        ? !s.hasGroqKey
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
    required this.isGroqMode,
    required this.hasGroqKey,
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

  final bool isGroqMode;
  final bool hasGroqKey;

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
