import 'dart:async';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_client/ui/screens/settings_screen.dart';

import 'package:flutter_client/ui/shared/widgets/refined_icon_button.dart';
import 'package:google_fonts/google_fonts.dart';

class HamburgerMenu extends StatelessWidget {
  const HamburgerMenu({super.key});

  static const _borderAlpha = 0.1;
  static const _menuElevation = 8.0;

  void _handleSelection(BuildContext context, String value) {
    switch (value) {
      case 'settings':
        unawaited(
          showDialog(
            context: context,
            builder: (ctx) => const SettingsScreen(),
          ),
        );

        return;
      case 'quit':
        unawaited(windowManager.close());

        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fontFamily = GoogleFonts.lexend().fontFamily;

    return PopupMenuButton<String>(
      tooltip: '', // Hide tooltip
      offset: const Offset(0, 32),
      color: const Color(0xFF1E1E23), // Matches surface color roughly
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        side: BorderSide(color: Colors.white.withValues(alpha: _borderAlpha)),
      ),
      elevation: _menuElevation,
      child: const RefinedIconButton(
        icon: Icons.menu,
        onTap: null, // Allow PopupMenuButton trigger
        iconSize: 20, // Smaller icon
      ),
      onSelected: (value) => _handleSelection(context, value),
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'settings',
          child: Row(
            children: [
              const Icon(Icons.settings, size: 18, color: Colors.white70),
              const SizedBox(width: 12),
              Text(
                'Open Settings',
                style: TextStyle(color: Colors.white, fontFamily: fontFamily),
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
                  fontFamily: fontFamily,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
