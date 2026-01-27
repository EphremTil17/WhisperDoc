import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/services/auth/auth_service.dart';
import 'package:flutter_client/ui/screens/home/dialogs/profile_hub_dialog.dart';

class ProfileHub extends StatefulWidget {
  const ProfileHub({super.key});

  @override
  State<ProfileHub> createState() => _ProfileHubState();
}

class _ProfileHubState extends State<ProfileHub> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final user = authService.currentUser;

    return Tooltip(
      message: 'Manage Profile',
      verticalOffset: 25,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            unawaited(
              showDialog(
                context: context,
                barrierColor: Colors.black.withValues(alpha: 0.7),
                builder: (context) => const ProfileHubDialog(),
              ),
            );
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: _isHovered
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _isHovered
                    ? Colors.white.withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.1),
                width: 1,
              ),
              boxShadow: _isHovered
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
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
                  color: _isHovered
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
