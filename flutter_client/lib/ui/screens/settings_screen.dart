import 'dart:async';
import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/ui/shared/widgets/glass_dialog.dart';
import 'package:flutter_client/infrastructure/theme/app_theme.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_client/ui/screens/settings/widgets/connection_section.dart';
import 'package:flutter_client/ui/screens/settings/widgets/auth_section.dart';
import 'package:flutter_client/ui/screens/settings/widgets/hotkey_section.dart';
import 'package:flutter_client/ui/screens/settings/widgets/automation_section.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _uriController;
  late TextEditingController _apiKeyController;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsService>();
    _uriController = TextEditingController(text: settings.serverUri);
    _apiKeyController = TextEditingController(text: settings.cachedApiKey);
  }

  @override
  void dispose() {
    _uriController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    final settings = context.read<SettingsService>();
    await settings.setServerUri(_uriController.text);
    await settings.setApiKey(_apiKeyController.text);
    if (mounted) {
      Navigator.of(context).pop();
    }
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
            onPressed: _saveSettings,
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConnectionSection(uriController: _uriController),
            const SizedBox(height: 16),
            AuthSection(
              uriController: _uriController,
              apiKeyController: _apiKeyController,
            ),
            const SizedBox(height: 16),
            const HotkeySection(),
            const SizedBox(height: 16),
            const AutomationSection(),
          ],
        ),
      ),
    );
  }
}
