import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/controllers/profile_controller.dart';
import 'package:flutter_client/controllers/recording_controller.dart';
import 'package:flutter_client/logic/mappers/home_status_mapper.dart';
import 'package:flutter_client/logic/models/model_selection_problem.dart';
import 'package:flutter_client/logic/models/transcription_source.dart';
import 'package:flutter_client/services/transcription/open_router_catalog.dart';
import 'package:flutter_client/services/transport/handshake_state_machine.dart';
import 'package:flutter_client/services/transport/server_problem.dart';
import 'package:flutter_client/services/transport/websocket_service.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/services/utility/update_service.dart';

/// Reads the services the home screen depends on and maps them to a
/// [HomeStatus]. Selects only the fields [HomeSignals] consumes so unrelated
/// changes (e.g. copy/paste toggles, prompt edits, history appends) do not
/// rebuild the stage, bottom bar or account indicator.
extension HomeStatusReader on BuildContext {
  HomeStatus watchHomeStatus() {
    final (source, style, hasApiKey, hasCloudKey) = select(
      (SettingsService s) => (
        s.transcriptionSource,
        s.dictationProfile,
        s.cachedApiKey?.isNotEmpty ?? false,
        s.hasCloudKey,
      ),
    );
    // Only OpenRouter has a model list; other sources never rebuild on it.
    final (modelProblem, isLoadingModels, modelListError) = select(
      (OpenRouterCatalog c) => source == TranscriptionSource.openRouter
          ? (c.selectionProblem, c.isRefreshing, c.lastError?.userMessage)
          : (ModelSelectionProblem.none, false, null),
    );
    // Signed in means holding credentials, not holding a socket: the
    // connection closes when idle and reopens on the next dictation.
    final hasSignIn = select((ProfileController p) => p.isAuthenticated);
    final (handshakeFailed, isBanned, serverProblem, isConnecting) = select(
      (WebSocketService ws) => (
        ws.handshakeState.state == HandshakeState.failed,
        ws.status == ConnectionStatus.banned,
        ws.serverProblem,
        ws.status == ConnectionStatus.connecting,
      ),
    );
    final serverHost = select(
      (WebSocketService ws) =>
          serverProblem == ServerProblem.untrusted ? ws.serverHost : '',
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
        source: source,
        hasCloudKey: hasCloudKey,
        modelProblem: modelProblem,
        isLoadingModels: isLoadingModels,
        modelListError: modelListError,
        isSignedIn: hasSignIn || hasApiKey,
        handshakeFailed: handshakeFailed,
        isBanned: isBanned,
        serverProblem: serverProblem,
        serverHost: serverHost,
        isConnecting: isConnecting,
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
