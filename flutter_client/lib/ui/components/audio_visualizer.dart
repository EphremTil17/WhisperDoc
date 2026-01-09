import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/services/audio_service.dart';
import 'package:flutter_client/ui/theme/app_theme.dart';

class AudioVisualizer extends StatelessWidget {
  const AudioVisualizer({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<double>(
      stream: context.read<AudioService>().amplitudeStream,
      initialData: 0.0,
      builder: (context, snapshot) {
        final amplitude = snapshot.data ?? 0.0;

        return Container(
          height: 40,
          width: 200,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(15, (index) {
              // Create a symmetrical waveform effect
              final distanceFromCenter = (index - 7).abs();
              final scale = 1.0 - (distanceFromCenter / 10.0);
              final height = 4.0 + (amplitude * 30.0 * scale);

              return AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                margin: const EdgeInsets.symmetric(horizontal: 2),
                width: 3,
                height: height,
                decoration: BoxDecoration(
                  color: AppTheme.crimsonPrimary.withValues(
                    alpha: 0.3 + (amplitude * 0.7),
                  ),
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: [
                    if (amplitude > 0.1)
                      BoxShadow(
                        color: AppTheme.crimsonPrimary.withValues(alpha: 0.3),
                        blurRadius: 4,
                        spreadRadius: 1,
                      ),
                  ],
                ),
              );
            }),
          ),
        );
      },
    );
  }
}
