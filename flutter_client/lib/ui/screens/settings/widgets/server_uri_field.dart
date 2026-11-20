import 'package:material_ui/material_ui.dart';

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
            hintText: 'ws://localhost:9989/ws',
            hintStyle: TextStyle(color: Colors.white24),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          ),
        ),
      ],
    );
  }
}
