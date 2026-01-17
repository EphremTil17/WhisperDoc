import 'package:flutter/material.dart';
import 'package:flutter_client/core/services/websocket_service.dart';
import 'package:flutter_client/core/services/transport_security_service.dart';

import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

class StatusBar extends StatelessWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    final wsService = context.watch<WebSocketService>();
    final status = wsService.status;
    final security = wsService.securityStatus;

    Color statusColor;
    String statusText;

    switch (status) {
      case ConnectionStatus.connected:
        final isEncrypted = security == SecurityStatus.secure;
        statusColor = isEncrypted
            ? Colors.greenAccent.withValues(alpha: 0.8)
            : Colors.orangeAccent.withValues(alpha: 0.8);
        statusText = isEncrypted
            ? "Connected (TLS 1.3 Encrypted)"
            : "Connected (Not Encrypted)";
        break;
      case ConnectionStatus.connecting:
        statusColor = Colors.orangeAccent.withValues(alpha: 0.8);
        statusText = "Connecting...";
        break;
      case ConnectionStatus.banned:
        statusColor = Colors.redAccent.withValues(alpha: 0.8);
        statusText = "Connection Banned";
        break;
      default:
        statusColor = Colors.white38;
        statusText = "Ready (Deep Sleep)";
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          statusText,
          style: TextStyle(
            color: statusColor,
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
