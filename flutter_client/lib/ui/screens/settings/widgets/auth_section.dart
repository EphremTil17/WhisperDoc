import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/services/transport/websocket_service.dart';
import 'package:flutter_client/services/auth/auth_service.dart';
import 'package:google_fonts/google_fonts.dart';

class AuthSection extends StatefulWidget {
  final TextEditingController uriController;
  final TextEditingController apiKeyController;

  const AuthSection({
    super.key,
    required this.uriController,
    required this.apiKeyController,
  });

  @override
  State<AuthSection> createState() => _AuthSectionState();
}

class _AuthSectionState extends State<AuthSection> {
  bool _showAdvanced = false;

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final settings = context.watch<SettingsService>();
    final wsService = context.watch<WebSocketService>();

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

        if (isAuthenticated)
          _buildUserCard(context, authService, user!)
        else
          _buildSignInCard(context, authService),

        const SizedBox(height: 24),

        // --- Advanced / Developer Settings ---
        InkWell(
          onTap: () => setState(() => _showAdvanced = !_showAdvanced),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(
                  _showAdvanced ? Icons.expand_less : Icons.expand_more,
                  color: Colors.white38,
                  size: 16,
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
          _buildManualApiKeySection(settings, wsService),
        ],
      ],
    );
  }

  Widget _buildUserCard(
    BuildContext context,
    AuthService auth,
    Map<String, dynamic> user,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          if (user['picture'] != null)
            CircleAvatar(
              radius: 20,
              backgroundImage: NetworkImage(user['picture'] as String),
            )
          else
            const CircleAvatar(
              radius: 20,
              backgroundColor: Colors.white10,
              child: Icon(Icons.person, color: Colors.white38, size: 20),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user['name'] as String? ?? 'WhisperUser',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  user['email'] as String? ?? 'Authenticated',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => auth.signOut(),
            icon: const Icon(Icons.logout, color: Colors.white30, size: 20),
            tooltip: 'Sign Out',
          ),
        ],
      ),
    );
  }

  Widget _buildSignInCard(BuildContext context, AuthService auth) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.blueAccent.withValues(alpha: 0.1),
            Colors.blueAccent.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          const Icon(Icons.security, color: Colors.blueAccent, size: 32),
          const SizedBox(height: 12),
          const Text(
            'Passwordless Connection',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Secure your voice data with Passkeys or Google',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => auth.signIn(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Sign in with Verified Identity',
                style: TextStyle(
                  fontFamily: GoogleFonts.lexend().fontFamily,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManualApiKeySection(
    SettingsService settings,
    WebSocketService wsService,
  ) {
    final tokenLabel = settings.getTokenLabel(widget.apiKeyController.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'MANUAL API KEY',
              style: TextStyle(color: Colors.white38, fontSize: 10),
            ),
            Text(
              tokenLabel,
              style: const TextStyle(color: Colors.blueGrey, fontSize: 9),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _SecureApiKeyField(controller: widget.apiKeyController),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _SecureApiKeyField extends StatefulWidget {
  final TextEditingController controller;
  const _SecureApiKeyField({required this.controller});
  @override
  State<_SecureApiKeyField> createState() => _SecureApiKeyFieldState();
}

class _SecureApiKeyFieldState extends State<_SecureApiKeyField> {
  bool _obscureText = true;
  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: _obscureText,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.black26,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        suffixIcon: IconButton(
          icon: Icon(
            _obscureText ? Icons.visibility_off : Icons.visibility,
            color: Colors.white38,
            size: 18,
          ),
          onPressed: () => setState(() => _obscureText = !_obscureText),
        ),
      ),
    );
  }
}
