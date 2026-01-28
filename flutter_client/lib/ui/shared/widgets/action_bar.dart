import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/services/transport/websocket_service.dart';
import 'package:flutter_client/services/auth/auth_service.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/ui/shared/widgets/refined_icon_button.dart';
import 'package:flutter_client/ui/screens/settings_screen.dart';
import 'package:flutter_client/ui/screens/home/dialogs/log_viewer_dialog.dart';
import 'package:flutter_client/ui/screens/home/dialogs/history_dialog.dart';
import 'package:flutter_client/infrastructure/theme/app_theme.dart';
import 'package:flutter_client/ui/screens/home/dialogs/profile_hub_dialog.dart';
import 'package:flutter_client/services/utility/update_service.dart';
import 'package:flutter_client/logic/mappers/connection_ui_map.dart';

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
        // 1. Incognito button
        Tooltip(
          message: isIncognitoMode ? 'Disable Incognito' : 'Enable Incognito',
          preferBelow: false,
          verticalOffset: 20,
          child: RefinedIconButton(
            icon: isIncognitoMode
                ? Icons.visibility_off
                : Icons.visibility_off_outlined,
            iconColor: isIncognitoMode ? Colors.orangeAccent : Colors.white38,
            iconSize: 16,
            onTap: onIncognitoTap,
          ),
        ),
        const SizedBox(width: 8),

        // 2. History button
        Tooltip(
          message: 'Recent Transcriptions',
          preferBelow: false,
          verticalOffset: 20,
          child: RefinedIconButton(
            icon: Icons.history,
            iconColor: Colors.white38,
            iconSize: 16,
            onTap: () => _showHistoryDialog(context),
          ),
        ),
        const SizedBox(width: 8),

        // 3. Connection Status Lock Icon (CENTER)
        Consumer4<
          WebSocketService,
          AuthService,
          SettingsService,
          UpdateService
        >(
          builder: (context, wsService, authService, settings, updateService, child) {
            // Map service states to UI descriptors using the pure logic mapper.
            final descriptor = ConnectionStateMapper.mapState(
              status: wsService.status,
              handshake: wsService.handshakeState.state,
              security: wsService.securityStatus,
              hasAnyCreds: wsService.hasValidCredentials,
              updateStatus: updateService.status,
            );

            return Tooltip(
              message: descriptor.tooltip,
              preferBelow: false,
              verticalOffset: 20,
              child: RefinedIconButton(
                icon: descriptor.icon,
                iconColor: descriptor.iconColor,
                iconSize: 18,
                isPulsing: descriptor.isPulsing,
                pulseColor: descriptor.pulseColor,
                onTap: () {
                  // Direct Action: If update required, go straight to Profile Hub
                  if (updateService.status == UpdateStatus.required) {
                    _showProfileHub(context);
                    return;
                  }

                  final status = wsService.status;
                  if (status == ConnectionStatus.connected ||
                      status == ConnectionStatus.connecting) {
                    return;
                  }

                  if (!wsService.hasValidCredentials) {
                    // One-Click Redirection: Direct to Settings if no auth
                    _showSettingsDialog(context);
                  } else {
                    // Ready to Connect
                    unawaited(wsService.connect());
                  }
                },
              ),
            );
          },
        ),
        const SizedBox(width: 8),

        // 4. Settings button
        Tooltip(
          message: 'System Settings',
          preferBelow: false,
          verticalOffset: 20,
          child: RefinedIconButton(
            icon: Icons.settings_outlined,
            iconColor: AppTheme.crimsonPrimary,
            iconSize: 18,
            onTap: () => _showSettingsDialog(context),
          ),
        ),
        const SizedBox(width: 8),

        // 5. Log button
        Tooltip(
          message: 'Debug Logs',
          preferBelow: false,
          verticalOffset: 20,
          child: RefinedIconButton(
            icon: Icons.terminal_outlined,
            iconColor: Colors.white38,
            iconSize: 16,
            onTap: () => _showLogDialog(context),
          ),
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

  void _showProfileHub(BuildContext context) {
    unawaited(
      showDialog(context: context, builder: (ctx) => const ProfileHubDialog()),
    );
  }

  void _showLogDialog(BuildContext context) {
    unawaited(
      showDialog(context: context, builder: (ctx) => const LogViewerDialog()),
    );
  }
}
