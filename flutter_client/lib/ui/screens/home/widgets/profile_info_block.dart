import 'package:flutter/material.dart';

class ProfileInfoBlock extends StatelessWidget {
  const ProfileInfoBlock({super.key, required this.user});

  static const _avatarRadius = 40.0;
  static const _placeholderBackgroundAlpha = 0.1;
  static const _emailAlpha = 0.6;
  static const _emailFontSize = 14.0;

  final Map<String, dynamic>? user;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (user?['picture'] case final String pictureUrl)
          CircleAvatar(
            radius: _avatarRadius,
            backgroundImage: NetworkImage(pictureUrl),
          )
        else
          CircleAvatar(
            radius: _avatarRadius,
            backgroundColor: Colors.white.withValues(
              alpha: _placeholderBackgroundAlpha,
            ),
            child: const Icon(
              Icons.person,
              size: _avatarRadius,
              color: Colors.white70,
            ),
          ),
        const SizedBox(height: 16),
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
            color: Colors.white.withValues(alpha: _emailAlpha),
            fontSize: _emailFontSize,
          ),
        ),
      ],
    );
  }
}
