import 'package:material_ui/material_ui.dart';
import 'package:flutter_client/ui/features/recording/recording.dart';
import 'package:flutter_client/ui/shared/widgets/transcribed_text_area.dart';
import 'package:provider/provider.dart';

class TranscriptionView extends StatelessWidget {
  const TranscriptionView({super.key});

  @override
  Widget build(BuildContext context) {
    final currentText = context.select(
      (RecordingController c) => c.currentText,
    );

    return Column(
      children: [
        const HotkeyHint(),
        const SizedBox(height: 12),
        Expanded(child: TranscribedTextArea(text: currentText)),
        const SizedBox(height: 12),
      ],
    );
  }
}
