import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/services/auth/auth_service.dart';
import 'package:flutter_client/ui/screens/settings/widgets/auth_sign_in_card.dart';
import 'package:flutter_client/ui/screens/settings/widgets/auth_user_card.dart';
import 'package:flutter_client/ui/screens/settings/widgets/manual_api_key_section.dart';

class AuthSection extends StatefulWidget {
  const AuthSection({
    super.key,
    required this.uriController,
    required this.apiKeyController,
  });

  final TextEditingController uriController;
  final TextEditingController apiKeyController;

  @override
  State<AuthSection> createState() => _AuthSectionState();
}

class _AuthSectionState extends State<AuthSection> {
  static const double _advancedTogglePadding = 8;
  static const double _advancedToggleIconSize = 16;

  bool _showAdvanced = false;

  void _toggleAdvanced() {
    setState(() => _showAdvanced = !_showAdvanced);
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final settings = context.watch<SettingsService>();

    final isAuthenticated = authService.isAuthenticated;
    final user = authService.currentUser;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // --- Primary OIDC Section ---
        const Text(
          'IDENTITY & ACCESS',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 12),

        if (isAuthenticated && user != null)
          AuthUserCard(authService: authService, user: user)
        else
          AuthSignInCard(authService: authService),

        const SizedBox(height: 24),

        // --- Advanced / Developer Settings ---
        InkWell(
          onTap: _toggleAdvanced,
          borderRadius: const BorderRadius.all(Radius.circular(8)),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: _advancedTogglePadding,
            ),
            child: Row(
              children: [
                Icon(
                  _showAdvanced ? Icons.expand_less : Icons.expand_more,
                  color: Colors.white38,
                  size: _advancedToggleIconSize,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Developer Settings (Manual API Key)',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),

        if (_showAdvanced) ...[
          const SizedBox(height: 12),
          ManualApiKeySection(
            settings: settings,
            apiKeyController: widget.apiKeyController,
          ),
        ],
      ],
    );
  }
}
