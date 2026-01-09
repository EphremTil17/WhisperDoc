import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_client/ui/screens/settings_screen.dart';

class HamburgerMenu extends StatelessWidget {
  const HamburgerMenu({super.key});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      splashRadius: 24,
      tooltip: '', // Hide tooltip
      icon: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: const Icon(Icons.menu, color: Colors.white70, size: 24),
      ),
      offset: const Offset(0, 32),
      color: const Color(0xFF1E1E23), // Matches surface color roughly
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      elevation: 8,
      onSelected: (value) async {
        switch (value) {
          case 'settings':
            await showDialog(
              context: context,
              builder: (ctx) => const SettingsScreen(),
            );
            break;
          case 'quit':
            await windowManager.close();
            break;
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(
          value: 'settings',
          child: Row(
            children: [
              Icon(Icons.settings, size: 18, color: Colors.white70),
              SizedBox(width: 12),
              Text(
                'Open Settings',
                style: TextStyle(
                  color: Colors.white,
                  fontFamily: 'Lexend', // Fallback if global theme fails
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'quit',
          child: Row(
            children: [
              Icon(Icons.exit_to_app, size: 18, color: Colors.redAccent),
              SizedBox(width: 12),
              Text('Quit', style: TextStyle(color: Colors.redAccent)),
            ],
          ),
        ),
      ],
    );
  }
}
