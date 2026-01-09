import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_client/ui/screens/settings_screen.dart';

import 'package:flutter_client/ui/components/refined_icon_button.dart';
import 'package:google_fonts/google_fonts.dart';

class HamburgerMenu extends StatelessWidget {
  const HamburgerMenu({super.key});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: '', // Hide tooltip
      offset: const Offset(0, 32),
      color: const Color(0xFF1E1E23), // Matches surface color roughly
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      elevation: 8,
      child: const RefinedIconButton(
        icon: Icons.menu,
        onTap: null, // Allow PopupMenuButton trigger
        iconSize: 20, // Smaller icon
      ),
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
        PopupMenuItem<String>(
          value: 'settings',
          child: Row(
            children: [
              const Icon(Icons.settings, size: 18, color: Colors.white70),
              const SizedBox(width: 12),
              Text(
                'Open Settings',
                style: TextStyle(
                  color: Colors.white,
                  fontFamily: GoogleFonts.lexend().fontFamily,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'quit',
          child: Row(
            children: [
              const Icon(Icons.exit_to_app, size: 18, color: Colors.redAccent),
              const SizedBox(width: 12),
              Text(
                'Quit',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontFamily: GoogleFonts.lexend().fontFamily,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
