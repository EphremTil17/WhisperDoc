import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_client/services/auth/auth_service.dart';
import 'package:google_fonts/google_fonts.dart';

class AuthSignInCard extends StatelessWidget {
  const AuthSignInCard({super.key, required this.authService});

  static const double _topGradientOpacity = 0.1;
  static const double _bottomGradientOpacity = 0.05;
  static const double _borderOpacity = 0.2;

  final AuthService authService;

  void _handleSignInPressed() {
    unawaited(authService.signIn());
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.blueAccent.withValues(alpha: _topGradientOpacity),
            Colors.blueAccent.withValues(alpha: _bottomGradientOpacity),
          ],
        ),
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        border: Border.all(
          color: Colors.blueAccent.withValues(alpha: _borderOpacity),
        ),
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
              onPressed: _handleSignInPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
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
}
