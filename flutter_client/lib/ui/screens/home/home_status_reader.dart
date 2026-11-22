import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/controllers/recording_controller.dart';
import 'package:flutter_client/logic/mappers/home_status_mapper.dart';
import 'package:flutter_client/services/transcription/groq_transcription_service.dart';
import 'package:flutter_client/services/transport/handshake_state_machine.dart';
import 'package:flutter_client/services/transport/websocket_service.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/services/utility/update_service.dart';

/// Reads the services the home screen depends on and maps them to a
/// [HomeStatus]. Selects only the fields [HomeSignals] consumes so unrelated
/// changes (e.g. copy/paste toggles, prompt edits, history appends) do not
/// rebuild the stage, bottom bar or account indicator.
extension HomeStatusReader on BuildContext {
  HomeStatus watchHomeStatus() {
    final (isGroqMode, style) = select(
      (SettingsService s) => (s.isGroqMode, s.dictationProfile),
    );
    final hasGroqKey = select(
      (GroqTranscriptionService g) => g.hasValidCredentials,
    );
    final (isSignedIn, handshakeFailed, isBanned) = select(
      (WebSocketService ws) => (
        ws.isAuthenticatedSession,
        ws.handshakeState.state == HandshakeState.failed,
        ws.status == ConnectionStatus.banned,
      ),
    );
    final updateStatus = select((UpdateService u) => u.status);
    final (
      inputStatus,
      isRecording,
      isTranscribing,
      hasText,
      showSilenceWarning,
    ) = select(
      (RecordingController r) => (
        r.inputStatus,
        r.isRecording,
        r.isTranscribing,
        r.currentText.isNotEmpty,
        r.showSilenceWarning,
      ),
    );

    return HomeStatusMapper.map(
      HomeSignals(
        isGroqMode: isGroqMode,
        hasGroqKey: hasGroqKey,
        isSignedIn: isSignedIn,
        handshakeFailed: handshakeFailed,
        isBanned: isBanned,
        updateStatus: updateStatus,
        inputStatus: inputStatus,
        isRecording: isRecording,
        isTranscribing: isTranscribing,
        // Text arrives before an LLM style rewrites it.
        isPolishing: style.requiresLlm && hasText,
        showSilenceWarning: showSilenceWarning,
        styleLabel: style.label,
      ),
    );
  }
}
