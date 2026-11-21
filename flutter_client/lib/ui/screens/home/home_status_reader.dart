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
/// [HomeStatus]. Each caller rebuilds when any of those services change, so
/// the stage, bottom bar and account indicator always agree.
extension HomeStatusReader on BuildContext {
  HomeStatus watchHomeStatus() {
    final settings = watch<SettingsService>();
    final recording = watch<RecordingController>();
    final groq = watch<GroqTranscriptionService>();
    final ws = watch<WebSocketService>();
    final update = watch<UpdateService>();
    final style = settings.dictationProfile;

    return HomeStatusMapper.map(
      HomeSignals(
        isGroqMode: settings.isGroqMode,
        hasGroqKey: groq.hasValidCredentials,
        isSignedIn: ws.isAuthenticatedSession,
        handshakeFailed: ws.handshakeState.state == HandshakeState.failed,
        isBanned: ws.status == ConnectionStatus.banned,
        updateStatus: update.status,
        inputStatus: recording.inputStatus,
        isRecording: recording.isRecording,
        isTranscribing: recording.isTranscribing,
        // Text arrives before an LLM style rewrites it.
        isPolishing: style.requiresLlm && recording.currentText.isNotEmpty,
        showSilenceWarning: recording.showSilenceWarning,
        styleLabel: style.label,
      ),
    );
  }
}
