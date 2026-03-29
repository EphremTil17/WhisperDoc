import 'package:flutter/material.dart';

class SecureKeyField extends StatefulWidget {
  const SecureKeyField({super.key, required this.controller});

  static const double _visibilityIconSize = 18;

  final TextEditingController controller;

  @override
  State<SecureKeyField> createState() => _SecureKeyFieldState();
}

class _SecureKeyFieldState extends State<SecureKeyField> {
  bool _obscureText = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: _obscureText,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.black26,
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          borderSide: BorderSide.none,
        ),
        suffixIcon: IconButton(
          icon: Icon(
            _obscureText ? Icons.visibility_off : Icons.visibility,
            color: Colors.white38,
            size: SecureKeyField._visibilityIconSize,
          ),
          onPressed: () => setState(() => _obscureText = !_obscureText),
        ),
      ),
    );
  }
}
