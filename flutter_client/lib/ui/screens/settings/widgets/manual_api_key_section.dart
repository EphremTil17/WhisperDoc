import 'package:material_ui/material_ui.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/ui/screens/settings/widgets/secure_key_field.dart';

class ManualApiKeySection extends StatelessWidget {
  const ManualApiKeySection({super.key, required this.apiKeyController});

  final TextEditingController apiKeyController;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'MANUAL API KEY',
              style: TextStyle(color: Colors.white38, fontSize: 10),
            ),
            // Tracks the field as the user types or pastes.
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: apiKeyController,
              builder: (context, value, _) => Text(
                SettingsService.getTokenLabel(value.text),
                style: const TextStyle(color: Colors.blueGrey, fontSize: 9),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SecureKeyField(controller: apiKeyController),
        const SizedBox(height: 12),
      ],
    );
  }
}
