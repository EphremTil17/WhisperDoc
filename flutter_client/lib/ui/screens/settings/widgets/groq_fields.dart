import 'package:flutter/material.dart';
import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import 'package:flutter_client/ui/screens/settings/widgets/secure_key_field.dart';

class GroqFields extends StatelessWidget {
  const GroqFields({
    super.key,
    required this.groqApiKeyController,
    required this.groqLanguageController,
    required this.groqPromptController,
  });

  static const int _promptMaxLines = 2;

  final TextEditingController groqApiKeyController;
  final TextEditingController groqLanguageController;
  final TextEditingController groqPromptController;

  @override
  Widget build(BuildContext context) {
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
                : 'Unsupported language code: "$code"';

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: groqLanguageController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(
                      borderRadius: const BorderRadius.all(Radius.circular(8)),
                      borderSide: languageError != null
                          ? const BorderSide(color: Colors.redAccent, width: 1)
                          : BorderSide.none,
                    ),
                    hintText: 'e.g. en, es, fr (empty = auto)',
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
        const SizedBox(height: 8),
        const Text(
          'PROMPT HINT',
          style: TextStyle(color: Colors.white38, fontSize: 10),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: groqPromptController,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          maxLines: _promptMaxLines,
          decoration: const InputDecoration(
            filled: true,
            fillColor: Colors.black26,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
              borderSide: BorderSide.none,
            ),
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
