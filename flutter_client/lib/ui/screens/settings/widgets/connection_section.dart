import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/services/websocket_service.dart';
import 'package:flutter_client/core/services/settings_service.dart';
import 'package:flutter_client/core/services/handshake_state_machine.dart';

class ConnectionSection extends StatelessWidget {
  final TextEditingController uriController;

  const ConnectionSection({super.key, required this.uriController});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'CONNECTION',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Server URI',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: uriController,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.black26,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            hintText: 'ws://localhost:9989/ws',
            hintStyle: const TextStyle(color: Colors.white24),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 14,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Consumer<WebSocketService>(
          builder: (context, wsService, child) {
            final status = wsService.status;
            final handshake = wsService.handshakeState.state;

            Color btnColor = Colors.white10;
            Color textColor = Colors.white;
            String btnText = 'Test Connection';

            if (handshake == HandshakeState.authenticated) {
              btnColor = Colors.green.withValues(alpha: 0.2);
              textColor = Colors.greenAccent;
              btnText = 'Authenticated ✓';
            } else if (handshake == HandshakeState.authenticating ||
                status == ConnectionStatus.connecting) {
              btnText = 'Connecting...';
            } else if (handshake == HandshakeState.failed) {
              btnColor = Colors.red.withValues(alpha: 0.2);
              textColor = Colors.redAccent;
              btnText = 'Failed ✗';
            } else if (status == ConnectionStatus.connected) {
              btnColor = Colors.green.withValues(alpha: 0.2);
              textColor = Colors.greenAccent;
              btnText = 'Connected';
            }

            return FilledButton(
              onPressed: () async {
                await context.read<SettingsService>().setServerUri(
                  uriController.text,
                );
                if (status != ConnectionStatus.connecting) {
                  unawaited(wsService.connect());
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
