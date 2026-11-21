import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_client/infrastructure/theme/app_icons.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/services/auth/auth_service.dart';
import 'package:flutter_client/ui/shared/widgets/app_button.dart';
import 'package:flutter_client/ui/shared/widgets/crisp_text.dart';

/// Sign-in prompt for self-hosted mode: a ruled panel with one action.
class AuthSignInCard extends StatelessWidget {
  const AuthSignInCard({super.key, required this.authService});

  static const double _iconSize = 24;

  final AuthService authService;

  void _handleSignInPressed() {
    unawaited(authService.signIn());
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.controlAll,
        border: Border.fromBorderSide(BorderSide(color: AppColors.rule)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpace.xs,
          children: [
            const Icon(AppIcons.keyRound, size: _iconSize, color: AppColors.text),
            const SizedBox(height: AppSpace.sm),
            CrispText(
              'Passwordless sign-in',
              textAlign: TextAlign.center,
              style: AppType.body.copyWith(fontWeight: FontWeight.w600),
            ),
            CrispText(
              'Use a passkey or Google to protect your voice data.',
              textAlign: TextAlign.center,
              style: AppType.caption.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: AppSpace.md),
            AppButton(
              label: 'Sign in',
              onPressed: _handleSignInPressed,
            ),
          ],
        ),
      ),
    );
  }
}
