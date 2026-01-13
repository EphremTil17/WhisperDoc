import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_client/ui/shared/widgets/refined_icon_button.dart';
import 'package:flutter_client/ui/features/recording/widgets/status_bar.dart';
import 'package:flutter_client/ui/screens/settings_screen.dart';
import 'package:flutter_client/ui/screens/log_viewer_dialog.dart';
import 'package:flutter_client/ui/screens/history_dialog.dart';
import 'package:flutter_client/ui/theme/app_theme.dart';

/// Bottom action bar with icon buttons for app controls
class ActionBar extends StatelessWidget {
  /// Whether incognito mode is active
  final bool isIncognitoMode;

  /// Callback when incognito button is tapped
  final VoidCallback onIncognitoTap;

  const ActionBar({
    super.key,
    required this.isIncognitoMode,
    required this.onIncognitoTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // LEFT SIDE - Incognito button
        RefinedIconButton(
          icon: isIncognitoMode
              ? Icons.visibility_off
              : Icons.visibility_off_outlined,
          iconColor: isIncognitoMode ? Colors.orangeAccent : Colors.white38,
          iconSize: 16,
          onTap: onIncognitoTap,
        ),
        const SizedBox(width: 8),

        // History button
        RefinedIconButton(
          icon: Icons.history,
          iconColor: Colors.white38,
          iconSize: 16,
          onTap: () => _showHistoryDialog(context),
        ),
        const SizedBox(width: 16),

        // CENTER - Status
        const StatusBar(),
        const SizedBox(width: 16),

        // RIGHT SIDE - Settings button
        RefinedIconButton(
          icon: Icons.settings_outlined,
          iconColor: AppTheme.crimsonPrimary,
          iconSize: 18,
          onTap: () => _showSettingsDialog(context),
        ),
        const SizedBox(width: 8),

        // Log button
        RefinedIconButton(
          icon: Icons.terminal_outlined,
          iconColor: Colors.white38,
          iconSize: 16,
          onTap: () => _showLogDialog(context),
        ),
      ],
    );
  }

  void _showHistoryDialog(BuildContext context) {
    unawaited(
      showDialog(context: context, builder: (ctx) => const HistoryDialog()),
    );
  }

  void _showSettingsDialog(BuildContext context) {
    unawaited(
      showDialog(context: context, builder: (ctx) => const SettingsScreen()),
    );
  }

  void _showLogDialog(BuildContext context) {
    unawaited(
      showDialog(context: context, builder: (ctx) => const LogViewerDialog()),
    );
  }
}
