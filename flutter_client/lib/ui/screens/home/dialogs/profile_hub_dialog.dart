import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_client/infrastructure/theme/app_theme.dart';
import 'package:flutter_client/ui/screens/home/dialogs/profile_hub_dialog_content.dart';

/// Mode-aware Profile Hub Dialog.
///
/// In backend mode: shows OIDC identity, update status, sign in/out.
/// In Groq mode: shows Groq Cloud status and a path to switch to WhisperDoc.
class ProfileHubDialog extends StatelessWidget {
  const ProfileHubDialog({super.key});

  static const double _blurSigma = 10;
  static const double _dialogWidth = 320;
  static const double _dialogPadding = 24;
  static const double _dialogRadius = 28;
  static const double _dialogBorderWidth = 1.5;
  static const double _dialogBorderAlpha = 0.1;
  static const double _dialogShadowAlpha = 0.3;
  static const double _dialogShadowBlurRadius = 30;
  static const double _dialogShadowOffsetY = 10;

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: _blurSigma, sigmaY: _blurSigma),
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: _dialogWidth,
            padding: const EdgeInsets.all(_dialogPadding),
            decoration: BoxDecoration(
              color: AppTheme.cardBackground,
              borderRadius: const BorderRadius.all(
                Radius.circular(_dialogRadius),
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: _dialogBorderAlpha),
                width: _dialogBorderWidth,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: _dialogShadowAlpha),
                  blurRadius: _dialogShadowBlurRadius,
                  offset: const Offset(0, _dialogShadowOffsetY),
                ),
              ],
            ),
            child: const ProfileHubDialogContent(),
          ),
        ),
      ),
    );
  }
}
