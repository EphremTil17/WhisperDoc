import 'package:flutter/material.dart';
import 'package:flutter_client/ui/features/recording/recording.dart';
import 'package:flutter_client/ui/shared/widgets/transcribed_text_area.dart';
import 'package:provider/provider.dart';

class TranscriptionView extends StatelessWidget {
  const TranscriptionView({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<RecordingController>();

    return Column(
      children: [
        const HotkeyHint(),
        const SizedBox(height: 12),
        Expanded(child: TranscribedTextArea(text: controller.currentText)),
        const SizedBox(height: 12),
      ],
    );
  }
}
