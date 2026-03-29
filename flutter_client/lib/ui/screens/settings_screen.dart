import 'dart:async';
import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/ui/shared/widgets/glass_dialog.dart';
import 'package:flutter_client/infrastructure/theme/app_theme.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_client/ui/screens/settings/widgets/connection_section.dart';
import 'package:flutter_client/ui/screens/settings/widgets/audio_section.dart';
import 'package:flutter_client/ui/screens/settings/widgets/auth_section.dart';
import 'package:flutter_client/ui/screens/settings/widgets/hotkey_section.dart';
import 'package:flutter_client/ui/screens/settings/widgets/automation_section.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _uriController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _groqApiKeyController = TextEditingController();
  final TextEditingController _groqLanguageController = TextEditingController();
  final TextEditingController _groqPromptController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsService>();
    _uriController.text = settings.serverUri;
    _apiKeyController.text = settings.cachedApiKey ?? '';
    _groqApiKeyController.text = settings.cachedGroqApiKey ?? '';
    _groqLanguageController.text = settings.groqLanguage;
    _groqPromptController.text = settings.groqPrompt;
  }

  Future<void> _saveSettings() async {
    final settings = context.read<SettingsService>();
    await settings.setServerUri(_uriController.text);
    await settings.setApiKey(_apiKeyController.text);
    await settings.setGroqApiKey(_groqApiKeyController.text);
    await settings.setGroqLanguage(_groqLanguageController.text);
    await settings.setGroqPrompt(_groqPromptController.text);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _handleDoneTap() {
    unawaited(_saveSettings());
  }

  @override
  void dispose() {
    _uriController.dispose();
    _apiKeyController.dispose();
    _groqApiKeyController.dispose();
    _groqLanguageController.dispose();
    _groqPromptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GlassDialog(
      title: 'Settings',
      shrinkWrap: true,
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Consumer<SettingsService>(
            builder: (context, settings, child) => Text(
              'v${settings.appVersion}',
              style: const TextStyle(color: Colors.white24, fontSize: 12),
            ),
          ),
          TextButton(
            onPressed: _handleDoneTap,
            child: Text(
              'Done',
              style: TextStyle(
                fontFamily: GoogleFonts.lexend().fontFamily,
                color: AppTheme.crimsonPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: Consumer<SettingsService>(
        builder: (context, settings, child) {
          final isGroqMode = settings.isGroqMode;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ConnectionSection(
                  uriController: _uriController,
                  groqApiKeyController: _groqApiKeyController,
                  groqLanguageController: _groqLanguageController,
                  groqPromptController: _groqPromptController,
                ),
                const SizedBox(height: 16),
                const AudioSection(),
                if (!isGroqMode) ...[
                  const SizedBox(height: 16),
                  AuthSection(
                    uriController: _uriController,
                    apiKeyController: _apiKeyController,
                  ),
                ],
                const SizedBox(height: 16),
                const HotkeySection(),
                const SizedBox(height: 16),
                const AutomationSection(),
              ],
            ),
          );
        },
      ),
    );
  }
}
