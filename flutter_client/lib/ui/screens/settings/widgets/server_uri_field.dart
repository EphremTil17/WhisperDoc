import 'package:flutter/material.dart';

class ServerUriField extends StatelessWidget {
  const ServerUriField({super.key, required this.uriController});

  final TextEditingController uriController;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Server URI',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: uriController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            filled: true,
            fillColor: Colors.black26,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
              borderSide: BorderSide.none,
            ),
            hintText: 'ws://localhost:9989/ws',
            hintStyle: TextStyle(color: Colors.white24),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          ),
        ),
      ],
    );
  }
}
