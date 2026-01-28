import 'package:flutter/material.dart';

class ProfileInfoBlock extends StatelessWidget {
  final Map<String, dynamic>? user;

  const ProfileInfoBlock({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (user?['picture'] != null)
          CircleAvatar(
            radius: 40,
            backgroundImage: NetworkImage(user!['picture'] as String),
          )
        else
          CircleAvatar(
            radius: 40,
            backgroundColor: Colors.white.withValues(alpha: 0.1),
            child: const Icon(Icons.person, size: 40, color: Colors.white70),
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
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}
