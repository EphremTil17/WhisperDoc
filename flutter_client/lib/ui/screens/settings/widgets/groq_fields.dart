import 'package:material_ui/material_ui.dart';
import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import 'package:flutter_client/ui/screens/settings/widgets/secure_key_field.dart';
import 'package:flutter_client/ui/shared/widgets/glass_dropdown.dart';

class GroqFields extends StatelessWidget {
  const GroqFields({
    super.key,
    required this.groqApiKeyController,
    required this.groqLanguageController,
    required this.groqPromptController,
    required this.selectedGroqModel,
    required this.onGroqModelChanged,
  });

  static const int _promptMaxLines = 2;
  static const double _fontSize = 13;

  final TextEditingController groqApiKeyController;
  final TextEditingController groqLanguageController;
  final TextEditingController groqPromptController;
  final String selectedGroqModel;
  final ValueChanged<String> onGroqModelChanged;

  @override
  Widget build(BuildContext context) {
    final TextStyle inputTextStyle = const TextStyle(
      color: Colors.white,
      fontSize: _fontSize,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Groq API Key',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            Text(
              'console.groq.com',
              style: TextStyle(color: Colors.white24, fontSize: 9),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SecureKeyField(controller: groqApiKeyController),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'LANGUAGE HINT',
                    style: TextStyle(color: Colors.white38, fontSize: 10),
                  ),
                  const SizedBox(height: 4),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: groqLanguageController,
                    builder: (context, value, _) {
                      final code = value.text.trim();
                      final languageError =
                          code.isEmpty || AppConstants.isValidGroqLanguage(code)
                          ? null
                          : 'Invalid code';

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: groqLanguageController,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: _fontSize,
                            ),
                            decoration: InputDecoration(
                              border: OutlineInputBorder(
                                borderRadius: const BorderRadius.all(
                                  Radius.circular(8),
                                ),
                                borderSide: languageError != null
                                    ? const BorderSide(
                                        color: Colors.redAccent,
                                        width: 1,
                                      )
                                    : BorderSide.none,
                              ),
                              hintText: 'e.g. en, es (auto)',
                              hintStyle: const TextStyle(
                                color: Colors.white24,
                                fontSize: 12,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                          ),
                          if (languageError case final error?) ...[
                            const SizedBox(height: 4),
                            Text(
                              error,
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'MODEL',
                    style: TextStyle(color: Colors.white38, fontSize: 10),
                  ),
                  const SizedBox(height: 4),
                  GlassDropdown<String>(
                    value:
                        AppConstants.groqSupportedModels.contains(
                          selectedGroqModel,
                        )
                        ? selectedGroqModel
                        : AppConstants.groqDefaultModel,
                    items: [
                      for (final model in AppConstants.groqSupportedModels)
                        GlassDropdownItem(
                          value: model,
                          label:
                              AppConstants.groqModelDisplayNames[model] ??
                              model,
                        ),
                    ],
                    onChanged: onGroqModelChanged,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'PROMPT HINT',
          style: TextStyle(color: Colors.white38, fontSize: 10),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: groqPromptController,
          style: inputTextStyle,
          maxLines: _promptMaxLines,
          decoration: const InputDecoration(
            hintText: 'Spelling/style hints (max 224 tokens)',
            hintStyle: TextStyle(color: Colors.white24, fontSize: 12),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'No backend needed. Free tier: 20 req/min.',
          style: TextStyle(color: Colors.white24, fontSize: 9),
        ),
      ],
    );
  }
}
