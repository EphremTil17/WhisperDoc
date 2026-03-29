import 'package:flutter/material.dart';

class ProfileHubAvatar extends StatelessWidget {
  const ProfileHubAvatar({required this.user, super.key});

  static const _avatarRadius = 14.0;
  static const _fallbackAvatarAlpha = 0.1;
  static const _avatarIconSize = 16.0;

  final Map<String, dynamic>? user;

  @override
  Widget build(BuildContext context) {
    if (user?['picture'] case final String pictureUrl) {
      return CircleAvatar(
        radius: _avatarRadius,
        backgroundImage: NetworkImage(pictureUrl),
      );
    }

    return CircleAvatar(
      radius: _avatarRadius,
      backgroundColor: Colors.white.withValues(alpha: _fallbackAvatarAlpha),
      child: const Icon(
        Icons.person,
        size: _avatarIconSize,
        color: Colors.white70,
      ),
    );
  }
}
