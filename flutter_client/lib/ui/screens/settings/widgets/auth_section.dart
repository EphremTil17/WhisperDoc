import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/services/settings_service.dart';
import 'package:flutter_client/core/services/websocket_service.dart';
import 'package:flutter_client/core/services/handshake_state_machine.dart';
import 'package:flutter_client/core/services/jwt_validator.dart';

class AuthSection extends StatelessWidget {
  final TextEditingController uriController;
  final TextEditingController apiKeyController;
  static final JWTValidator _jwtValidator = JWTValidator();

  const AuthSection({
    super.key,
    required this.uriController,
    required this.apiKeyController,
  });

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final tokenLabel = settings.getTokenLabel(apiKeyController.text);

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
        if (apiKeyController.text.isNotEmpty)
          Builder(
            builder: (context) {
              final warning = _jwtValidator.getExpiryWarning(
                apiKeyController.text,
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
        _SecureApiKeyField(controller: apiKeyController),
        const SizedBox(height: 16),
        Consumer<WebSocketService>(
          builder: (context, wsService, child) {
            final status = wsService.status;
            final handshake = wsService.handshakeState.state;

            Color btnColor = Colors.white10;
            Color textColor = Colors.white;
            String btnText = 'Authenticate';

            if (handshake == HandshakeState.authenticated) {
              btnColor = Colors.green.withValues(alpha: 0.2);
              textColor = Colors.greenAccent;
              btnText = 'Authenticated ✓';
            } else if (handshake == HandshakeState.authenticating ||
                status == ConnectionStatus.connecting) {
              btnText = 'Connecting...';
            } else if (handshake == HandshakeState.failed) {
              btnColor = Colors.red.withValues(alpha: 0.4);
              textColor = Colors.white;
              btnText = 'Authentication Failed. Retry?';
            } else if (status == ConnectionStatus.connected) {
              btnColor = Colors.green.withValues(alpha: 0.2);
              textColor = Colors.greenAccent;
              btnText = 'Connected';
            }

            return FilledButton(
              onPressed: () async {
                if (status != ConnectionStatus.connecting) {
                  unawaited(
                    wsService.connect(
                      uriOverride: uriController.text,
                      apiKeyOverride: apiKeyController.text,
                    ),
                  );
                }
              },
              style: FilledButton.styleFrom(
                backgroundColor: btnColor,
                foregroundColor: textColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(btnText),
            );
          },
        ),
      ],
    );
  }
}

class _SecureApiKeyField extends StatefulWidget {
  final TextEditingController controller;

  const _SecureApiKeyField({required this.controller});

  @override
  State<_SecureApiKeyField> createState() => _SecureApiKeyFieldState();
}

class _SecureApiKeyFieldState extends State<_SecureApiKeyField> {
  bool _obscureText = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: _obscureText,
      maxLines: _obscureText ? 1 : null,
      keyboardType: TextInputType.multiline,
      style: const TextStyle(color: Colors.white, fontSize: 13),
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
