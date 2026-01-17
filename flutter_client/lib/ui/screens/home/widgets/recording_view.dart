import 'package:flutter/material.dart';
import 'package:flutter_client/core/services/settings_service.dart';
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
    final isRecording = controller.isRecording;

    return Column(
      children: [
        const SizedBox(height: 16),
        FloatingCapsule(
          isRecording: isRecording,
          onTap: () => controller.toggleRecording(),
        ),
        const SizedBox(height: 8),
        if (settings.showVisualizer)
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
