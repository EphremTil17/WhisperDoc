import 'package:flutter/material.dart';
import 'package:flutter_client/services/transport/websocket_service.dart';
import 'package:flutter_client/services/transport/handshake_state_machine.dart';
import 'package:flutter_client/services/transport/transport_security_service.dart';
import 'package:flutter_client/services/transcription/groq_transcription_service.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/services/auth/auth_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

class StatusBar extends StatelessWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();

    // Groq mode: show Groq-specific status.
    if (settings.isGroqMode) {
      return _buildGroqStatus(context);
    }

    // Backend mode: existing WebSocket status.
    return _buildBackendStatus(context);
  }

  Widget _buildGroqStatus(BuildContext context) {
    final groqService = context.watch<GroqTranscriptionService>();

    Color statusColor;
    String statusText;

    switch (groqService.status) {
      case GroqTranscriptionStatus.idle:
        if (groqService.hasValidCredentials) {
          statusColor = Colors.greenAccent.withValues(alpha: 0.8);
          statusText = 'Groq Cloud (Ready)';
        } else {
          statusColor = Colors.orangeAccent.withValues(alpha: 0.8);
          statusText = 'Groq Cloud (No API Key)';
        }
      case GroqTranscriptionStatus.buffering:
        statusColor = Colors.greenAccent.withValues(alpha: 0.8);
        statusText = 'Recording (Groq Cloud)';
      case GroqTranscriptionStatus.transcribing:
        statusColor = Colors.greenAccent.withValues(alpha: 0.8);
        statusText = 'Transcribing via Groq...';
      case GroqTranscriptionStatus.error:
        statusColor = Colors.redAccent.withValues(alpha: 0.8);
        statusText = 'Groq Cloud Error';
    }

    return _buildRow(statusColor, statusText);
  }

  Widget _buildBackendStatus(BuildContext context) {
    final wsService = context.watch<WebSocketService>();
    final authService = context.watch<AuthService>();

    final status = wsService.status;
    final security = wsService.securityStatus;
    final handshake = wsService.handshakeState.state;
    final isAuthenticated = authService.isAuthenticated;

    Color statusColor;
    String statusText;

    switch (status) {
      case ConnectionStatus.banned:
        statusColor = Colors.redAccent.withValues(alpha: 0.8);
        statusText = "Connection Banned";
      case ConnectionStatus.connected:
        final isEncrypted = security == SecurityStatus.secure;
        statusColor = isEncrypted
            ? Colors.greenAccent.withValues(alpha: 0.8)
            : Colors.orangeAccent.withValues(alpha: 0.8);

        final String authType = isAuthenticated ? "OIDC Verified" : "API Key";
        statusText = isEncrypted
            ? "Connected ($authType • TLS 1.3)"
            : "Connected ($authType • Unencrypted)";
      case ConnectionStatus.connecting:
        statusColor = Colors.orangeAccent.withValues(alpha: 0.8);
        statusText = "Connecting...";
      default:
        if (handshake == HandshakeState.failed) {
          statusColor = Colors.redAccent.withValues(alpha: 0.8);
          statusText = "Authentication Failed";
        } else {
          statusColor = Colors.white38;
          statusText = "Ready (Deep Sleep)";
        }
    }

    return _buildRow(statusColor, statusText);
  }

  Widget _buildRow(Color color, String text) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w400,
            fontFamily: GoogleFonts.lexend().fontFamily,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}
