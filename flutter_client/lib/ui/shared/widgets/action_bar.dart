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
import 'package:flutter_client/services/transcription/groq_transcription_service.dart';
import 'package:flutter_client/logic/mappers/connection_ui_map.dart';
import 'package:flutter_client/controllers/recording_controller.dart';
import 'package:flutter_client/ui/features/recording/widgets/profile_action_button.dart';
import 'package:flutter_client/ui/shared/widgets/lockable_control.dart';

/// Bottom action bar with icon buttons for app controls
class ActionBar extends StatelessWidget {
  const ActionBar({
    super.key,
    required this.isIncognitoMode,
    required this.onIncognitoTap,
  });

  static const double _tooltipVerticalOffset = 20;
  static const double _compactIconSize = 16;
  static const double _standardIconSize = 18;
  static const double _iconSpacing = 8;
  static const double _silenceWarningPulseAlpha = 0.3;

  /// Whether incognito mode is active
  final bool isIncognitoMode;

  /// Callback when incognito button is tapped
  final VoidCallback onIncognitoTap;

  VoidCallback _buildGroqConnectionTapHandler(
    BuildContext context,
    GroqTranscriptionService groqService,
  ) {
    return () {
      if (!groqService.hasValidCredentials) {
        _showSettingsDialog(context);
      }
    };
  }

  VoidCallback _buildBackendConnectionTapHandler(
    BuildContext context,
    WebSocketService wsService,
    UpdateService updateService,
  ) {
    return () {
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
        _showSettingsDialog(context);
      } else {
        unawaited(wsService.connect());
      }
    };
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

  @override
  Widget build(BuildContext context) {
    final isSessionActive = context
        .watch<RecordingController>()
        .isSessionActive;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 1. Incognito button
        LockableControl(
          locked: isSessionActive,
          child: Consumer<SettingsService>(
            builder: (context, settings, child) {
              final isCloudActive = settings.isGroqMode;
              final String incognitoTooltip;
              if (isIncognitoMode && isCloudActive) {
                incognitoTooltip = 'Incognito (Local Only)';
              } else if (isIncognitoMode) {
                incognitoTooltip = 'Disable Incognito';
              } else {
                incognitoTooltip = 'Enable Incognito';
              }

              return Tooltip(
                message: incognitoTooltip,
                preferBelow: false,
                verticalOffset: _tooltipVerticalOffset,
                child: RefinedIconButton(
                  icon: isIncognitoMode
                      ? Icons.visibility_off
                      : Icons.visibility_off_outlined,
                  iconColor: isIncognitoMode
                      ? Colors.orangeAccent
                      : Colors.white38,
                  iconSize: _compactIconSize,
                  onTap: onIncognitoTap,
                ),
              );
            },
          ),
        ),
        const SizedBox(width: _iconSpacing),

        // 2. History button
        LockableControl(
          locked: isSessionActive,
          child: Tooltip(
            message: 'Recent Transcriptions',
            preferBelow: false,
            verticalOffset: _tooltipVerticalOffset,
            child: RefinedIconButton(
              icon: Icons.history,
              iconColor: Colors.white38,
              iconSize: _compactIconSize,
              onTap: () => _showHistoryDialog(context),
            ),
          ),
        ),
        const SizedBox(width: _iconSpacing),

        // 3. Connection Status Lock / Cloud Icon (CENTER)
        LockableControl(
          locked: isSessionActive,
          child:
              Consumer4<
                WebSocketService,
                AuthService,
                SettingsService,
                UpdateService
              >(
                builder:
                    (
                      context,
                      wsService,
                      authService,
                      settings,
                      updateService,
                      child,
                    ) {
                      // Groq mode: show cloud icon, bypass backend state entirely.
                      if (settings.isGroqMode) {
                        final groqService = context
                            .watch<GroqTranscriptionService>();
                        final descriptor = ConnectionStateMapper.mapGroqState(
                          hasGroqKey: groqService.hasValidCredentials,
                          status: groqService.status,
                        );

                        return Tooltip(
                          message: descriptor.tooltip,
                          preferBelow: false,
                          verticalOffset: _tooltipVerticalOffset,
                          child: RefinedIconButton(
                            icon: descriptor.icon,
                            iconColor: descriptor.iconColor,
                            iconSize: _standardIconSize,
                            isPulsing: descriptor.isPulsing,
                            pulseColor: descriptor.pulseColor,
                            onTap: _buildGroqConnectionTapHandler(
                              context,
                              groqService,
                            ),
                          ),
                        );
                      }

                      // Backend mode: existing logic unchanged.
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
                        verticalOffset: _tooltipVerticalOffset,
                        child: RefinedIconButton(
                          icon: descriptor.icon,
                          iconColor: descriptor.iconColor,
                          iconSize: _standardIconSize,
                          isPulsing: descriptor.isPulsing,
                          pulseColor: descriptor.pulseColor,
                          onTap: _buildBackendConnectionTapHandler(
                            context,
                            wsService,
                            updateService,
                          ),
                        ),
                      );
                    },
              ),
        ),
        const SizedBox(width: _iconSpacing),

        // 4. Settings button
        LockableControl(
          locked: isSessionActive,
          child: Tooltip(
            message: 'System Settings',
            preferBelow: false,
            verticalOffset: _tooltipVerticalOffset,
            child: RefinedIconButton(
              icon: Icons.settings_outlined,
              iconColor: AppTheme.crimsonPrimary,
              iconSize: _standardIconSize,
              onTap: () => _showSettingsDialog(context),
            ),
          ),
        ),
        const SizedBox(width: _iconSpacing),

        // 5. Log button
        LockableControl(
          locked: isSessionActive,
          child: Tooltip(
            message: 'Debug Logs',
            preferBelow: false,
            verticalOffset: _tooltipVerticalOffset,
            child: RefinedIconButton(
              icon: Icons.terminal_outlined,
              iconColor: Colors.white38,
              iconSize: _compactIconSize,
              onTap: () => _showLogDialog(context),
            ),
          ),
        ),

        // 6. Silence Warning (Conditional - EXCLUDED from lock)
        Consumer<RecordingController>(
          builder: (context, controller, child) {
            if (!controller.showSilenceWarning) return const SizedBox.shrink();

            return Padding(
              padding: const EdgeInsets.only(left: _iconSpacing),
              child: Tooltip(
                message: 'No audio detected. Check Microphone Settings.',
                preferBelow: false,
                verticalOffset: _tooltipVerticalOffset,
                child: RefinedIconButton(
                  icon: Icons.warning_amber_rounded,
                  iconColor: Colors.orangeAccent,
                  iconSize: _standardIconSize,
                  isPulsing: true,
                  pulseColor: Colors.orangeAccent.withValues(
                    alpha: _silenceWarningPulseAlpha,
                  ),
                  onTap: () => _showSettingsDialog(context),
                ),
              ),
            );
          },
        ),

        const SizedBox(width: _iconSpacing),

        // 7. Dictation Profile Selector (Far Right)
        Consumer<SettingsService>(
          builder: (context, settings, child) {
            final isLocked = isSessionActive || !settings.isGroqMode;
            final tooltip = !settings.isGroqMode
                ? 'Available in Groq Cloud mode'
                : 'Unavailable while recording';

            return LockableControl(
              locked: isLocked,
              tooltipMessage: tooltip,
              child: const ProfileActionButton(),
            );
          },
        ),
      ],
    );
  }
}
