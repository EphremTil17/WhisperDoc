import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/services/settings_service.dart';
import 'package:flutter_client/core/services/jwt_validator.dart';

class AuthSection extends StatelessWidget {
  static final JWTValidator _jwtValidator = JWTValidator();

  const AuthSection({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final tokenLabel = settings.getTokenLabel(settings.cachedApiKey ?? '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'API KEY',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: tokenLabel.contains('JWT')
                    ? Colors.blue.withValues(alpha: 0.2)
                    : Colors.purple.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: tokenLabel.contains('JWT')
                      ? Colors.blue.withValues(alpha: 0.5)
                      : Colors.purple.withValues(alpha: 0.5),
                  width: 1,
                ),
              ),
              child: Text(
                tokenLabel,
                style: TextStyle(
                  color: tokenLabel.contains('JWT')
                      ? Colors.blueAccent
                      : Colors.purpleAccent,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (settings.cachedApiKey != null && settings.cachedApiKey!.isNotEmpty)
          Builder(
            builder: (context) {
              final warning = _jwtValidator.getExpiryWarning(
                settings.cachedApiKey!,
              );
              if (warning == null) return const SizedBox.shrink();

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.orange.withValues(alpha: 0.15),
                        Colors.orange.withValues(alpha: 0.05),
                      ],
                    ),
                    border: Border.all(
                      color: Colors.orangeAccent.withValues(alpha: 0.3),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.access_time,
                        color: Colors.orangeAccent,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          warning,
                          style: const TextStyle(
                            color: Colors.orangeAccent,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        _SecureApiKeyField(
          initialValue: settings.cachedApiKey ?? '',
          onChanged: (val) => settings.setApiKey(val),
        ),
      ],
    );
  }
}

class _SecureApiKeyField extends StatefulWidget {
  final String initialValue;
  final ValueChanged<String> onChanged;

  const _SecureApiKeyField({
    required this.initialValue,
    required this.onChanged,
  });

  @override
  State<_SecureApiKeyField> createState() => _SecureApiKeyFieldState();
}

class _SecureApiKeyFieldState extends State<_SecureApiKeyField> {
  late TextEditingController _controller;
  bool _obscureText = true;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      obscureText: _obscureText,
      maxLines: _obscureText ? 1 : null,
      keyboardType: TextInputType.multiline,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.black26,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        hintText: 'Enter your API key or JWT token',
        hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        suffixIcon: IconButton(
          icon: Icon(
            _obscureText ? Icons.visibility_off : Icons.visibility,
            color: Colors.white38,
            size: 18,
          ),
          onPressed: () => setState(() => _obscureText = !_obscureText),
        ),
      ),
    );
  }
}
