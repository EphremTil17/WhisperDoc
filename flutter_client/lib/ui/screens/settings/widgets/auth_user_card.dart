import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_client/services/auth/auth_service.dart';

class AuthUserCard extends StatelessWidget {
  const AuthUserCard({
    super.key,
    required this.authService,
    required this.user,
  });

  static const double _cardBackgroundOpacity = 0.05;
  static const double _avatarRadius = 20;
  static const double _logoutIconSize = 20;

  final AuthService authService;
  final Map<String, dynamic> user;

  void _handleSignOutPressed() {
    unawaited(authService.signOut());
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: _cardBackgroundOpacity),
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        border: const Border.fromBorderSide(BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          if (user['picture'] != null)
            CircleAvatar(
              radius: _avatarRadius,
              backgroundImage: NetworkImage(user['picture'] as String),
            )
          else
            const CircleAvatar(
              radius: _avatarRadius,
              backgroundColor: Colors.white10,
              child: Icon(
                Icons.person,
                color: Colors.white38,
                size: _avatarRadius,
              ),
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
            onPressed: _handleSignOutPressed,
            icon: const Icon(
              Icons.logout,
              color: Colors.white30,
              size: _logoutIconSize,
            ),
            tooltip: 'Sign Out',
          ),
        ],
      ),
    );
  }
}
