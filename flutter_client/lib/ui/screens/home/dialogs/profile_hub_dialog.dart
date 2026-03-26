import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/controllers/profile_controller.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/services/transcription/groq_transcription_service.dart';
import 'package:flutter_client/ui/screens/settings_screen.dart';
import 'package:flutter_client/infrastructure/theme/app_theme.dart';
import 'package:flutter_client/ui/shared/widgets/update_card.dart';
import 'package:flutter_client/ui/screens/home/widgets/profile_info_block.dart';

/// Mode-aware Profile Hub Dialog.
///
/// In backend mode: shows OIDC identity, update status, sign in/out.
/// In Groq mode: shows Groq Cloud status and a path to switch to WhisperDoc.
class ProfileHubDialog extends StatelessWidget {
  const ProfileHubDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();

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
            child: settings.isGroqMode
                ? _buildGroqContent(context, settings)
                : _buildBackendContent(context),
          ),
        ),
      ),
    );
  }

  // ── Groq Cloud Mode ──────────────────────────────────────────────────

  Widget _buildGroqContent(BuildContext context, SettingsService settings) {
    final groqService = context.watch<GroqTranscriptionService>();
    final profileController = context.watch<ProfileController>();
    final hasKey = groqService.hasValidCredentials;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Cloud identity indicator
        CircleAvatar(
          radius: 40,
          backgroundColor: hasKey
              ? Colors.greenAccent.withValues(alpha: 0.1)
              : Colors.orangeAccent.withValues(alpha: 0.1),
          child: Icon(
            hasKey ? Icons.cloud_done : Icons.cloud_off,
            size: 40,
            color: hasKey ? Colors.greenAccent : Colors.orangeAccent,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Groq Cloud',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          hasKey ? 'Direct Transcription (Ready)' : 'API Key Required',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 14,
          ),
        ),

        const SizedBox(height: 24),
        const Divider(color: Colors.white10),

        // Update card (GitHub-based in Groq mode)
        UpdateCard(
          status: profileController.updateStatus,
          descriptor: profileController.updateUI,
          downloadUrl: profileController.latestDownloadUrl,
        ),

        const SizedBox(height: 16),

        // Configure Groq → opens Settings (already in Groq mode)
        if (!hasKey)
          _buildActionButton(
            context,
            icon: Icons.settings,
            label: 'Configure Groq API Key',
            color: Colors.orangeAccent,
            onTap: () {
              Navigator.pop(context);
              unawaited(
                showDialog(
                  context: context,
                  builder: (ctx) => const SettingsScreen(),
                ),
              );
            },
          ),

        if (hasKey) const SizedBox(height: 0),

        // Switch to WhisperDoc backend
        _buildActionButton(
          context,
          icon: Icons.swap_horiz,
          label: 'WhisperDoc Backend',
          color: Colors.greenAccent,
          onTap: () async {
            Navigator.pop(context);
            await settings.setTranscriptionMode('backend');
            // If not OIDC authenticated and no backend API key, open Settings
            // so the user can configure the backend connection.
            if (!profileController.isAuthenticated &&
                (settings.cachedApiKey?.isEmpty ?? true)) {
              if (context.mounted) {
                unawaited(
                  showDialog(
                    context: context,
                    builder: (ctx) => const SettingsScreen(),
                  ),
                );
              }
            }
          },
        ),

        const SizedBox(height: 12),

        // Close
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
    );
  }

  // ── Backend Mode ─────────────────────────────────────────────────────

  Widget _buildBackendContent(BuildContext context) {
    final profileController = context.watch<ProfileController>();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1. Identity Component
        ProfileInfoBlock(user: profileController.currentUser),

        const SizedBox(height: 24),
        const Divider(color: Colors.white10),

        // 2. Update Component
        UpdateCard(
          status: profileController.updateStatus,
          descriptor: profileController.updateUI,
          downloadUrl: profileController.latestDownloadUrl,
        ),

        const SizedBox(height: 16),

        // 3. Auth Actions — split row: [Groq Cloud] [Sign Out]
        _buildBackendActionRow(context, profileController),

        const SizedBox(height: 12),

        // 4. Close
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
    );
  }

  Widget _buildBackendActionRow(
    BuildContext context,
    ProfileController controller,
  ) {
    final bool isAuth = controller.isAuthenticated;
    final settings = context.read<SettingsService>();

    // When authenticated: split [Groq Cloud (1/3)] [Sign Out (2/3)]
    // When not authenticated: full-width Sign In
    if (!isAuth) {
      return _buildActionButton(
        context,
        icon: Icons.login,
        label: 'Sign In',
        color: AppTheme.crimsonPrimary,
        onTap: () {
          Navigator.pop(context);
          unawaited(
            showDialog(
              context: context,
              builder: (ctx) => const SettingsScreen(),
            ),
          );
        },
      );
    }

    return Row(
      children: [
        // 1/3 — Switch to Groq Cloud (neutral white tone)
        Expanded(
          flex: 1,
          child: _buildCompactButton(
            icon: Icons.cloud,
            label: 'Groq',
            color: Colors.white70,
            onTap: () async {
              Navigator.pop(context);
              await settings.setTranscriptionMode('groq');
              // If no Groq key, open Settings so user can enter it
              if (settings.cachedGroqApiKey?.isEmpty ?? true) {
                if (context.mounted) {
                  unawaited(
                    showDialog(
                      context: context,
                      builder: (ctx) => const SettingsScreen(),
                    ),
                  );
                }
              }
            },
          ),
        ),
        const SizedBox(width: 8),
        // 2/3 — Sign Out (red)
        Expanded(
          flex: 2,
          child: _buildCompactButton(
            icon: Icons.logout,
            label: 'Sign Out',
            color: Colors.redAccent,
            onTap: () async {
              Navigator.pop(context);
              await controller.signOut();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCompactButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withValues(alpha: 0.1),
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 0,
      ).copyWith(
        side: WidgetStateProperty.all(
          BorderSide(color: color.withValues(alpha: 0.3), width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared Helpers ───────────────────────────────────────────────────

  Widget _buildActionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.1),
          foregroundColor: color,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ).copyWith(
          side: WidgetStateProperty.all(
            BorderSide(
              color: color.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 8),
            Text(label),
          ],
        ),
      ),
    );
  }
}
