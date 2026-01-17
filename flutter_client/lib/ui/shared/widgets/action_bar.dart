import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/services/websocket_service.dart';
import 'package:flutter_client/core/services/transport_security_service.dart';
import 'package:flutter_client/core/services/handshake_state_machine.dart';
import 'package:flutter_client/ui/shared/widgets/refined_icon_button.dart';
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
        // 1. Incognito button
        RefinedIconButton(
          icon: isIncognitoMode
              ? Icons.visibility_off
              : Icons.visibility_off_outlined,
          iconColor: isIncognitoMode ? Colors.orangeAccent : Colors.white38,
          iconSize: 16,
          onTap: onIncognitoTap,
        ),
        const SizedBox(width: 8),

        // 2. History button
        RefinedIconButton(
          icon: Icons.history,
          iconColor: Colors.white38,
          iconSize: 16,
          onTap: () => _showHistoryDialog(context),
        ),
        const SizedBox(width: 8),

        // 3. Connection Status Lock Icon (CENTER)
        Consumer<WebSocketService>(
          builder: (context, wsService, child) {
            final status = wsService.status;
            final handshake = wsService.handshakeState.state;
            final security = wsService.securityStatus;

            Color iconColor;
            IconData iconData = Icons.lock_outline;

            if (handshake == HandshakeState.failed) {
              iconColor = AppTheme.crimsonPrimary;
              iconData = Icons.lock_open;
            } else if (status == ConnectionStatus.connected) {
              if (security == SecurityStatus.secure) {
                // Faint Green for secure WSS
                iconColor = Colors.greenAccent.withValues(alpha: 0.4);
                iconData = Icons.lock;
              } else {
                // Faint Amber/Orange for unsecure WS (Local)
                iconColor = Colors.orangeAccent.withValues(alpha: 0.4);
                iconData = Icons.lock_open;
              }
            } else if (status == ConnectionStatus.connecting) {
              iconColor = Colors.orangeAccent.withValues(alpha: 0.6);
            } else if (status == ConnectionStatus.banned) {
              iconColor = AppTheme.crimsonPrimary;
              iconData = Icons.block;
            } else {
              // Disconnected / Deep Sleep - Reddish/Inactive
              iconColor = AppTheme.crimsonPrimary.withValues(alpha: 0.4);
            }

            return RefinedIconButton(
              icon: iconData,
              iconColor: iconColor,
              iconSize: 18,
              onTap: () {
                if (status != ConnectionStatus.connected &&
                    status != ConnectionStatus.connecting) {
                  unawaited(wsService.connect());
                }
              },
            );
          },
        ),
        const SizedBox(width: 8),

        // 4. Settings button
        RefinedIconButton(
          icon: Icons.settings_outlined,
          iconColor: AppTheme.crimsonPrimary,
          iconSize: 18,
          onTap: () => _showSettingsDialog(context),
        ),
        const SizedBox(width: 8),

        // 5. Log button
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
