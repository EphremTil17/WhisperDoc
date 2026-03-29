import 'package:flutter/material.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/services/transport/websocket_service.dart';
import 'package:flutter_client/services/transport/handshake_state_machine.dart';
import 'package:flutter_client/services/transcription/groq_transcription_service.dart';
import 'package:flutter_client/ui/features/recording/recording.dart';
import 'package:flutter_client/ui/shared/widgets/audio_visualizer.dart';
import 'package:flutter_client/ui/shared/widgets/floating_capsule.dart';
import 'package:provider/provider.dart';

class RecordingView extends StatelessWidget {
  const RecordingView({super.key});

  static const _statusFontSize = 12.0;
  static const _visualizerPlaceholderHeight = 40.0;
  static const _visualizerFadeDuration = Duration(milliseconds: 200);

  static String _unauthorizedMessage({
    required bool isGroqMode,
    required bool isFailed,
    required WebSocketService wsService,
  }) {
    if (isGroqMode) return 'Please add a Groq API key in Settings.';

    if (isFailed) {
      final handshakeError = wsService.lastHandshakeError;
      if (handshakeError?.contains('Update') == true) {
        return 'Update Required. Please check Profile Hub.';
      }

      return handshakeError ?? 'Authentication Failed.';
    }

    return 'Please authenticate in Settings to begin.';
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<RecordingController>();
    final settings = context.watch<SettingsService>();
    final wsService = context.watch<WebSocketService>();
    final groqService = context.watch<GroqTranscriptionService>();

    final isRecording = controller.isRecording;
    final isGroqMode = settings.isGroqMode;

    // Mode-aware authorization check
    final isAuthorized = isGroqMode
        ? groqService.hasValidCredentials
        : wsService.isAuthenticatedSession;

    // Capsule disabled during Groq transcription upload
    final bool capsuleEnabled = isAuthorized && !controller.isTranscribing;

    final isFailed =
        !isGroqMode && wsService.handshakeState.state == HandshakeState.failed;

    return Column(
      children: [
        const SizedBox(height: 16),
        FloatingCapsule(
          isRecording: isRecording,
          enabled: capsuleEnabled,
          onTap: () => controller.toggleRecording(),
        ),
        const SizedBox(height: 12),
        if (controller.isTranscribing)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Transcribing via Groq Cloud...',
              style: TextStyle(
                color: Colors.blueAccent,
                fontSize: _statusFontSize,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          )
        else if (!isAuthorized)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              _unauthorizedMessage(
                isGroqMode: isGroqMode,
                isFailed: isFailed,
                wsService: wsService,
              ),
              style: TextStyle(
                color: isFailed ? Colors.redAccent : Colors.white38,
                fontSize: _statusFontSize,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          )
        else if (settings.showVisualizer)
          AnimatedOpacity(
            opacity: isRecording ? 1.0 : 0.0,
            duration: _visualizerFadeDuration,
            child: const AudioVisualizer(),
          )
        else
          const SizedBox(height: _visualizerPlaceholderHeight),
        const SizedBox(height: 8),
      ],
    );
  }
}
