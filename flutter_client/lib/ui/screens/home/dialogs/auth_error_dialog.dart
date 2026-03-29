import 'package:flutter/material.dart';
import 'package:flutter_client/ui/screens/settings_screen.dart';
import 'dart:async';

class AuthErrorDialog extends StatelessWidget {
  const AuthErrorDialog({super.key, required this.error});

  final String error;

  void _handleVerifySettings(BuildContext context) {
    Navigator.of(context).pop();
    unawaited(
      showDialog(
        context: context,
        builder: (context) => const SettingsScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1a1a2e),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        side: BorderSide(color: Colors.redAccent, width: 1),
      ),
      title: const Row(
        children: [
          Icon(Icons.error_outline, color: Colors.redAccent),
          SizedBox(width: 12),
          Text(
            'Authentication Failed',
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
        ],
      ),
      content: Text(
        '$error. Please verify your API Key or JWT Token in settings.',
        style: const TextStyle(color: Colors.white70, fontSize: 14),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close', style: TextStyle(color: Colors.white54)),
        ),
        ElevatedButton(
          onPressed: () => _handleVerifySettings(context),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
          child: const Text(
            'Verify Settings',
            style: TextStyle(color: Colors.white),
          ),
        ),
      ],
    );
  }
}
