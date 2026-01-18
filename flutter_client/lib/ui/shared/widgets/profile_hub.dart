import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/services/auth_service.dart';
import 'package:flutter_client/ui/screens/home/dialogs/profile_hub_dialog.dart';

class ProfileHub extends StatelessWidget {
  const ProfileHub({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final user = authService.currentUser;

    return InkWell(
      onTap: () {
        unawaited(
          showDialog(
            context: context,
            barrierColor: Colors.black.withValues(alpha: 0.7),
            builder: (context) => const ProfileHubDialog(),
          ),
        );
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (user?['picture'] != null)
              CircleAvatar(
                radius: 14,
                backgroundImage: NetworkImage(user!['picture'] as String),
              )
            else
              CircleAvatar(
                radius: 14,
                backgroundColor: Colors.white.withValues(alpha: 0.1),
                child: const Icon(
                  Icons.person,
                  size: 16,
                  color: Colors.white70,
                ),
              ),
            const SizedBox(width: 8),
            Icon(
              Icons.menu,
              size: 20,
              color: Colors.white.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}
