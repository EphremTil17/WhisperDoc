import 'dart:async';
import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import 'package:flutter_client/core/services/settings_service.dart';
import 'package:flutter_client/ui/shared/widgets/glass_dialog.dart';
import 'package:flutter_client/ui/theme/app_theme.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
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

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsService>();
    _uriController = TextEditingController(text: settings.serverUri);
  }

  @override
  void dispose() {
    _uriController.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    final settings = context.read<SettingsService>();
    await settings.setServerUri(_uriController.text);
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
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) {
              final version = snapshot.data?.version ?? '...';
              return Text(
                'v$version',
                style: const TextStyle(color: Colors.white24, fontSize: 12),
              );
            },
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
            AuthSection(),
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
