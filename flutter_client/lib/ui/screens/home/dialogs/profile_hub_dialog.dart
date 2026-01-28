import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/controllers/profile_controller.dart';
import 'package:flutter_client/ui/screens/settings_screen.dart';
import 'package:flutter_client/infrastructure/theme/app_theme.dart';
import 'package:flutter_client/ui/shared/widgets/update_card.dart';
import 'package:flutter_client/ui/screens/home/widgets/profile_info_block.dart';

/// The Profile Hub Dialog - Now lean and modular.
/// Responsibility: Orchestration only.
class ProfileHubDialog extends StatelessWidget {
  const ProfileHubDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final profileController = context.watch<ProfileController>();

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 320,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.cardBackground,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. Identity Component (Extracted)
                ProfileInfoBlock(user: profileController.currentUser),

                const SizedBox(height: 24),
                const Divider(color: Colors.white10),

                // 2. Update Component (Extracted & Shared)
                UpdateCard(
                  status: profileController.updateStatus,
                  descriptor: profileController.updateUI,
                  downloadUrl: profileController.latestDownloadUrl,
                ),

                const SizedBox(height: 16),

                // 3. Auth Actions
                _buildAuthButton(context, profileController),

                const SizedBox(height: 12),

                // 4. Close Action
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Close',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAuthButton(BuildContext context, ProfileController controller) {
    final bool isAuth = controller.isAuthenticated;
    final Color primaryColor = isAuth
        ? Colors.redAccent
        : AppTheme.crimsonPrimary;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () async {
          Navigator.pop(context);
          if (isAuth) {
            await controller.signOut();
          } else {
            unawaited(
              showDialog(
                context: context,
                builder: (ctx) => const SettingsScreen(),
              ),
            );
          }
        },
        style:
            ElevatedButton.styleFrom(
              backgroundColor: primaryColor.withValues(alpha: 0.1),
              foregroundColor: primaryColor,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 0,
            ).copyWith(
              side: WidgetStateProperty.all(
                BorderSide(
                  color: primaryColor.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
            ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isAuth ? Icons.logout : Icons.login, size: 20),
            const SizedBox(width: 8),
            Text(isAuth ? 'Sign Out' : 'Sign In'),
          ],
        ),
      ),
    );
  }
}
