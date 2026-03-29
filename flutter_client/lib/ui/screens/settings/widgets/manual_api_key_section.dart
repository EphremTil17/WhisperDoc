import 'package:flutter/material.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/ui/screens/settings/widgets/secure_key_field.dart';

class ManualApiKeySection extends StatelessWidget {
  const ManualApiKeySection({
    super.key,
    required this.settings,
    required this.apiKeyController,
  });

  final SettingsService settings;
  final TextEditingController apiKeyController;

  @override
  Widget build(BuildContext context) {
    final tokenLabel = settings.getTokenLabel(apiKeyController.text);

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
            Text(
              tokenLabel,
              style: const TextStyle(color: Colors.blueGrey, fontSize: 9),
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
