import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/services/websocket_service.dart';
import 'package:flutter_client/core/services/transport_security_service.dart';
import 'package:flutter_client/core/services/handshake_state_machine.dart';
import 'package:flutter_client/core/services/auth_service.dart';
import 'package:flutter_client/core/services/settings_service.dart';
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
        Consumer3<WebSocketService, AuthService, SettingsService>(
          builder: (context, wsService, authService, settings, child) {
            final status = wsService.status;
            final handshake = wsService.handshakeState.state;
            final security = wsService.securityStatus;

            // Check if we have ANY way to authenticate (OIDC or API Key)
            final bool hasOidc = authService.isAuthenticated;
            // Note: SettingsService.cachedApiKey is synchronous, good for UI checks
            final bool hasApiKey = settings.cachedApiKey?.isNotEmpty ?? false;
            final bool hasAnyCreds = hasOidc || hasApiKey;

            final bool isDisconnected = status == ConnectionStatus.disconnected;
            
            // Pulse logic:
            // 1. Teal/Green Pulse: Have credentials, but not connected (Ready to Connect)
            // 2. Crimson/Amber Pulse: No credentials at all (Action Required)
            final bool shouldPulse = isDisconnected;
            final Color pulseColor = hasAnyCreds ? Colors.greenAccent : Colors.orangeAccent;

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

            final String tooltipMsg;
            if (status == ConnectionStatus.connected) {
              tooltipMsg = security == SecurityStatus.secure ? 'Securely Connected' : 'Connected (Unencrypted)';
            } else if (status == ConnectionStatus.connecting) {
              tooltipMsg = 'Connecting to Server...';
            } else if (status == ConnectionStatus.banned) {
              tooltipMsg = 'Access Denied (Banned)';
            } else if (isDisconnected && hasAnyCreds) {
              tooltipMsg = 'Identity Verified. Click to Connect.';
            } else if (isDisconnected && !hasAnyCreds) {
              tooltipMsg = 'Authentication Required. Click to Setup.';
            } else {
              tooltipMsg = 'Disconnected. Click to Connect.';
            }

            return Tooltip(
              message: tooltipMsg,
              preferBelow: false,
              verticalOffset: 20,
              child: RefinedIconButton(
                icon: iconData,
                iconColor: iconColor,
                iconSize: 18,
                isPulsing: shouldPulse,
                pulseColor: shouldPulse ? pulseColor : null,
                onTap: () {
                  if (status == ConnectionStatus.connected || status == ConnectionStatus.connecting) {
                    return;
                  }

                  if (!hasAnyCreds) {
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

  void _showLogDialog(BuildContext context) {
    unawaited(
      showDialog(context: context, builder: (ctx) => const LogViewerDialog()),
    );
  }
}
