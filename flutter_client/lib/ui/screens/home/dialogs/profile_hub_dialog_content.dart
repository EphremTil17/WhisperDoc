import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/controllers/profile_controller.dart';
import 'package:flutter_client/infrastructure/theme/app_theme.dart';
import 'package:flutter_client/services/transcription/groq_transcription_service.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/ui/screens/home/widgets/profile_info_block.dart';
import 'package:flutter_client/ui/screens/settings_screen.dart';
import 'package:flutter_client/ui/shared/widgets/update_card.dart';

class ProfileHubDialogContent extends StatelessWidget {
  const ProfileHubDialogContent({super.key});

  static const double _avatarRadius = 40;
  static const double _avatarBackgroundAlpha = 0.1;
  static const double _statusIconSize = 40;
  static const double _titleFontSize = 18;
  static const double _statusFontSize = 14;
  static const double _statusTextAlpha = 0.6;
  static const double _closeTextAlpha = 0.4;
  static const double _sectionSpacing = 24;
  static const double _contentSpacing = 16;
  static const double _labelSpacing = 4;
  static const double _closeButtonSpacing = 12;
  static const int _groqButtonFlex = 1;
  static const int _signOutButtonFlex = 2;
  static const double _buttonBackgroundAlpha = 0.1;
  static const double _buttonBorderAlpha = 0.3;
  static const double _buttonBorderWidth = 1;
  static const double _buttonBorderRadius = 12;
  static const double _buttonElevation = 0;
  static const double _compactButtonPaddingVertical = 14;
  static const double _compactIconSize = 16;
  static const double _compactIconSpacing = 6;
  static const double _compactLabelFontSize = 12;
  static const double _actionButtonPaddingVertical = 16;
  static const double _actionIconSize = 20;
  static const double _actionIconSpacing = 8;
  static const double _backendRowSpacing = 8;
  static const String _backendMode = 'backend';
  static const String _groqMode = 'groq';

  VoidCallback _buildCloseDialogHandler(BuildContext context) {
    return () {
      _closeDialog(context);
    };
  }

  VoidCallback _buildOpenSettingsHandler(BuildContext context) {
    return () {
      _openSettingsDialog(context);
    };
  }

  VoidCallback _buildSwitchToBackendHandler(
    BuildContext context,
    SettingsService settings,
    ProfileController profileController,
  ) {
    return () {
      unawaited(_switchToBackend(context, settings, profileController));
    };
  }

  VoidCallback _buildSwitchToGroqHandler(
    BuildContext context,
    SettingsService settings,
  ) {
    return () {
      unawaited(_switchToGroq(context, settings));
    };
  }

  VoidCallback _buildSignOutHandler(
    BuildContext context,
    ProfileController controller,
  ) {
    return () {
      unawaited(_signOut(context, controller));
    };
  }

  void _closeDialog(BuildContext context) {
    Navigator.pop(context);
  }

  void _openSettingsDialog(BuildContext context) {
    Navigator.pop(context);
    unawaited(
      showDialog<void>(
        context: context,
        builder: (ctx) => const SettingsScreen(),
      ),
    );
  }

  Future<void> _switchToBackend(
    BuildContext context,
    SettingsService settings,
    ProfileController profileController,
  ) async {
    Navigator.pop(context);
    await settings.setTranscriptionMode(_backendMode);

    if (!profileController.isAuthenticated &&
        (settings.cachedApiKey?.isEmpty ?? true) &&
        context.mounted) {
      _openSettingsDialog(context);
    }
  }

  Future<void> _switchToGroq(
    BuildContext context,
    SettingsService settings,
  ) async {
    Navigator.pop(context);
    await settings.setTranscriptionMode(_groqMode);

    if ((settings.cachedGroqApiKey?.isEmpty ?? true) && context.mounted) {
      _openSettingsDialog(context);
    }
  }

  Future<void> _signOut(
    BuildContext context,
    ProfileController controller,
  ) async {
    Navigator.pop(context);
    await controller.signOut();
  }

  ButtonStyle _buildButtonStyle({
    required Color color,
    required EdgeInsetsGeometry padding,
  }) {
    return ElevatedButton.styleFrom(
      backgroundColor: color.withValues(alpha: _buttonBackgroundAlpha),
      foregroundColor: color,
      padding: padding,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(_buttonBorderRadius)),
      ),
      elevation: _buttonElevation,
    ).copyWith(
      side: WidgetStatePropertyAll(
        BorderSide(
          color: color.withValues(alpha: _buttonBorderAlpha),
          width: _buttonBorderWidth,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final closeDialog = _buildCloseDialogHandler(context);

    if (settings.isGroqMode) {
      final groqService = context.watch<GroqTranscriptionService>();
      final profileController = context.watch<ProfileController>();
      final openSettings = _buildOpenSettingsHandler(context);
      final switchToBackend = _buildSwitchToBackendHandler(
        context,
        settings,
        profileController,
      );
      final hasGroqKey = groqService.hasValidCredentials;

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: _avatarRadius,
            backgroundColor: hasGroqKey
                ? Colors.greenAccent.withValues(alpha: _avatarBackgroundAlpha)
                : Colors.orangeAccent.withValues(alpha: _avatarBackgroundAlpha),
            child: Icon(
              hasGroqKey ? Icons.cloud_done : Icons.cloud_off,
              size: _statusIconSize,
              color: hasGroqKey ? Colors.greenAccent : Colors.orangeAccent,
            ),
          ),
          const SizedBox(height: _contentSpacing),
          const Text(
            'Groq Cloud',
            style: TextStyle(
              color: Colors.white,
              fontSize: _titleFontSize,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: _labelSpacing),
          Text(
            hasGroqKey ? 'Direct Transcription (Ready)' : 'API Key Required',
            style: TextStyle(
              color: Colors.white.withValues(alpha: _statusTextAlpha),
              fontSize: _statusFontSize,
            ),
          ),
          const SizedBox(height: _sectionSpacing),
          const Divider(color: Colors.white10),
          UpdateCard(
            status: profileController.updateStatus,
            descriptor: profileController.updateUI,
            downloadUrl: profileController.latestDownloadUrl,
          ),
          const SizedBox(height: _contentSpacing),
          if (!hasGroqKey)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: openSettings,
                style: _buildButtonStyle(
                  color: Colors.orangeAccent,
                  padding: const EdgeInsets.symmetric(
                    vertical: _actionButtonPaddingVertical,
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.settings, size: _actionIconSize),
                    SizedBox(width: _actionIconSpacing),
                    Text('Configure Groq API Key'),
                  ],
                ),
              ),
            ),
          if (!hasGroqKey) const SizedBox(height: _contentSpacing),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: switchToBackend,
              style: _buildButtonStyle(
                color: Colors.greenAccent,
                padding: const EdgeInsets.symmetric(
                  vertical: _actionButtonPaddingVertical,
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.swap_horiz, size: _actionIconSize),
                  SizedBox(width: _actionIconSpacing),
                  Text('WhisperDoc Backend'),
                ],
              ),
            ),
          ),
          const SizedBox(height: _closeButtonSpacing),
          TextButton(
            onPressed: closeDialog,
            child: Text(
              'Close',
              style: TextStyle(
                color: Colors.white.withValues(alpha: _closeTextAlpha),
              ),
            ),
          ),
        ],
      );
    }

    final profileController = context.watch<ProfileController>();
    final openSettings = _buildOpenSettingsHandler(context);
    final switchToGroq = _buildSwitchToGroqHandler(context, settings);
    final signOut = _buildSignOutHandler(context, profileController);

    final authActions = !profileController.isAuthenticated
        ? SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: openSettings,
              style: _buildButtonStyle(
                color: AppTheme.crimsonPrimary,
                padding: const EdgeInsets.symmetric(
                  vertical: _actionButtonPaddingVertical,
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.login, size: _actionIconSize),
                  SizedBox(width: _actionIconSpacing),
                  Text('Sign In'),
                ],
              ),
            ),
          )
        : Row(
            children: [
              Expanded(
                flex: _groqButtonFlex,
                child: ElevatedButton(
                  onPressed: switchToGroq,
                  style: _buildButtonStyle(
                    color: Colors.white70,
                    padding: const EdgeInsets.symmetric(
                      vertical: _compactButtonPaddingVertical,
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cloud, size: _compactIconSize),
                      SizedBox(width: _compactIconSpacing),
                      Flexible(
                        child: Text(
                          'Groq',
                          style: TextStyle(
                            fontSize: _compactLabelFontSize,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: _backendRowSpacing),
              Expanded(
                flex: _signOutButtonFlex,
                child: ElevatedButton(
                  onPressed: signOut,
                  style: _buildButtonStyle(
                    color: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(
                      vertical: _compactButtonPaddingVertical,
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.logout, size: _compactIconSize),
                      SizedBox(width: _compactIconSpacing),
                      Flexible(
                        child: Text(
                          'Sign Out',
                          style: TextStyle(
                            fontSize: _compactLabelFontSize,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ProfileInfoBlock(user: profileController.currentUser),
        const SizedBox(height: _sectionSpacing),
        const Divider(color: Colors.white10),
        UpdateCard(
          status: profileController.updateStatus,
          descriptor: profileController.updateUI,
          downloadUrl: profileController.latestDownloadUrl,
        ),
        const SizedBox(height: _contentSpacing),
        authActions,
        const SizedBox(height: _closeButtonSpacing),
        TextButton(
          onPressed: closeDialog,
          child: Text(
            'Close',
            style: TextStyle(
              color: Colors.white.withValues(alpha: _closeTextAlpha),
            ),
          ),
        ),
      ],
    );
  }
}
