import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/infrastructure/theme/app_theme.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/controllers/recording_controller.dart';
import 'package:flutter_client/ui/screens/settings/widgets/groq_fields.dart';
import 'package:flutter_client/ui/screens/settings/widgets/mode_toggle.dart';
import 'package:flutter_client/ui/screens/settings/widgets/server_uri_field.dart';

class ConnectionSection extends StatelessWidget {
  const ConnectionSection({
    super.key,
    required this.uriController,
    required this.groqApiKeyController,
    required this.groqLanguageController,
    required this.groqPromptController,
  });

  final TextEditingController uriController;
  final TextEditingController groqApiKeyController;
  final TextEditingController groqLanguageController;
  final TextEditingController groqPromptController;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final controller = context.watch<RecordingController>();
    final isGroqMode = settings.isGroqMode;
    final sessionActive = controller.isRecording || controller.isTranscribing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('CONNECTION', style: AppTheme.sectionTitleStyle),
            if (sessionActive) ...[
              const SizedBox(width: 8),
              const Text(
                '(Active Session)',
                style: TextStyle(color: Colors.orangeAccent, fontSize: 9),
              ),
            ],
            const Spacer(),
            ModeToggle(
              isGroqMode: isGroqMode,
              enabled: !sessionActive,
              settings: settings,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (isGroqMode)
          GroqFields(
            groqApiKeyController: groqApiKeyController,
            groqLanguageController: groqLanguageController,
            groqPromptController: groqPromptController,
          )
        else
          ServerUriField(uriController: uriController),
      ],
    );
  }
}
