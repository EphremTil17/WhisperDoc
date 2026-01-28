import 'package:flutter/material.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/services/transport/websocket_service.dart';
import 'package:flutter_client/services/transport/handshake_state_machine.dart';
import 'package:flutter_client/ui/features/recording/recording.dart';
import 'package:flutter_client/ui/shared/widgets/audio_visualizer.dart';
import 'package:flutter_client/ui/shared/widgets/floating_capsule.dart';
import 'package:provider/provider.dart';

class RecordingView extends StatelessWidget {
  const RecordingView({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<RecordingController>();
    final settings = context.watch<SettingsService>();
    final wsService = context.watch<WebSocketService>();

    final isRecording = controller.isRecording;
    final isAuthorized = wsService.isAuthenticatedSession;
    final isFailed = wsService.handshakeState.state == HandshakeState.failed;

    return Column(
      children: [
        const SizedBox(height: 16),
        FloatingCapsule(
          isRecording: isRecording,
          enabled: isAuthorized,
          onTap: () => controller.toggleRecording(),
        ),
        const SizedBox(height: 12),
        if (!isAuthorized)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              isFailed
                  ? (wsService.lastHandshakeError?.contains('Update') == true
                        ? 'Update Required. Please check Profile Hub.'
                        : (wsService.lastHandshakeError ??
                              'Authentication Failed.'))
                  : 'Please authenticate in Settings to begin.',
              style: TextStyle(
                color: isFailed ? Colors.redAccent : Colors.white38,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          )
        else if (settings.showVisualizer)
          AnimatedOpacity(
            opacity: isRecording ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: const AudioVisualizer(),
          )
        else
          const SizedBox(height: 40),
        const SizedBox(height: 8),
      ],
    );
  }
}
