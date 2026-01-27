import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/services/auth/auth_service.dart';
import 'package:flutter_client/ui/screens/settings_screen.dart';
import 'package:flutter_client/infrastructure/theme/app_theme.dart';

class ProfileHubDialog extends StatelessWidget {
  const ProfileHubDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final user = authService.currentUser;

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
                // Profile Picture / Avatar
                if (user?['picture'] != null)
                  CircleAvatar(
                    radius: 40,
                    backgroundImage: NetworkImage(user!['picture'] as String),
                  )
                else
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    child: const Icon(
                      Icons.person,
                      size: 40,
                      color: Colors.white70,
                    ),
                  ),
                const SizedBox(height: 16),

                // Name & Email
                Text(
                  user?['name'] as String? ?? 'WhisperUser',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  user?['email'] as String? ?? 'Anonymous Session',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 14,
                  ),
                ),

                const SizedBox(height: 24),
                const Divider(color: Colors.white10),
                const SizedBox(height: 16),

                // Auth Button (Sign Out or Sign In)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      if (authService.isAuthenticated) {
                        await authService.signOut();
                      } else {
                        // Open Settings Dialog (as you requested, redirect to settings)
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
                          backgroundColor:
                              (authService.isAuthenticated
                                      ? Colors.redAccent
                                      : AppTheme.crimsonPrimary)
                                  .withValues(alpha: 0.1),
                          foregroundColor: authService.isAuthenticated
                              ? Colors.redAccent
                              : AppTheme.crimsonPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ).copyWith(
                          side: WidgetStateProperty.all(
                            BorderSide(
                              color:
                                  (authService.isAuthenticated
                                          ? Colors.redAccent
                                          : AppTheme.crimsonPrimary)
                                      .withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                        ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          authService.isAuthenticated
                              ? Icons.logout
                              : Icons.login,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          authService.isAuthenticated ? 'Sign Out' : 'Sign In',
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Close Button
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
}
