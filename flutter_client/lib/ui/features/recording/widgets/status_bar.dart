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

  static const double _statusColorAlpha = 0.8;
  static const double _statusDotSize = 6;
  static const double _statusSpacing = 8;
  static const double _statusFontSize = 11;
  static const double _statusLetterSpacing = 0.2;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    Color statusColor;
    String statusText;

    // Groq mode: show Groq-specific status.
    if (settings.isGroqMode) {
      final groqService = context.watch<GroqTranscriptionService>();

      if (groqService.status == GroqTranscriptionStatus.idle) {
        if (groqService.hasValidCredentials) {
          statusColor = Colors.greenAccent.withValues(alpha: _statusColorAlpha);
          statusText = 'Groq Cloud (Ready)';
        } else {
          statusColor = Colors.orangeAccent.withValues(
            alpha: _statusColorAlpha,
          );
          statusText = 'Groq Cloud (No API Key)';
        }
      } else if (groqService.status == GroqTranscriptionStatus.buffering) {
        statusColor = Colors.greenAccent.withValues(alpha: _statusColorAlpha);
        statusText = 'Recording (Groq Cloud)';
      } else if (groqService.status == GroqTranscriptionStatus.transcribing) {
        statusColor = Colors.greenAccent.withValues(alpha: _statusColorAlpha);
        statusText = 'Transcribing via Groq...';
      } else {
        statusColor = Colors.redAccent.withValues(alpha: _statusColorAlpha);
        statusText = 'Groq Cloud Error';
      }
    } else {
      // Backend mode: existing WebSocket status.
      final wsService = context.watch<WebSocketService>();
      final authService = context.watch<AuthService>();

      final status = wsService.status;
      final security = wsService.securityStatus;
      final handshake = wsService.handshakeState.state;
      final isAuthenticated = authService.isAuthenticated;

      if (status == ConnectionStatus.banned) {
        statusColor = Colors.redAccent.withValues(alpha: _statusColorAlpha);
        statusText = 'Connection Banned';
      } else if (status == ConnectionStatus.connected) {
        final isEncrypted = security == SecurityStatus.secure;
        statusColor = isEncrypted
            ? Colors.greenAccent.withValues(alpha: _statusColorAlpha)
            : Colors.orangeAccent.withValues(alpha: _statusColorAlpha);

        final authType = isAuthenticated ? 'OIDC Verified' : 'API Key';
        statusText = isEncrypted
            ? 'Connected ($authType • TLS 1.3)'
            : 'Connected ($authType • Unencrypted)';
      } else if (status == ConnectionStatus.connecting) {
        statusColor = Colors.orangeAccent.withValues(alpha: _statusColorAlpha);
        statusText = 'Connecting...';
      } else if (handshake == HandshakeState.failed) {
        statusColor = Colors.redAccent.withValues(alpha: _statusColorAlpha);
        statusText = 'Authentication Failed';
      } else {
        statusColor = Colors.white38;
        statusText = 'Ready (Deep Sleep)';
      }
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: _statusDotSize,
          height: _statusDotSize,
          decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: _statusSpacing),
        Text(
          statusText,
          style: TextStyle(
            color: statusColor,
            fontSize: _statusFontSize,
            fontWeight: FontWeight.w400,
            fontFamily: GoogleFonts.lexend().fontFamily,
            letterSpacing: _statusLetterSpacing,
          ),
        ),
      ],
    );
  }
}
