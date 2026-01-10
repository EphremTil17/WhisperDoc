import 'package:flutter/material.dart';
import 'package:flutter_client/core/services/websocket_service.dart';

import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

class StatusBar extends StatelessWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ConnectionStatus>(
      stream: context.read<WebSocketService>().onStatusChanged,
      initialData: ConnectionStatus.disconnected,
      builder: (context, snapshot) {
        final status = snapshot.data ?? ConnectionStatus.disconnected;
        Color statusColor;
        String statusText;

        switch (status) {
          case ConnectionStatus.connected:
            statusColor = Colors.greenAccent;
            statusText = "Connected";
            break;
          case ConnectionStatus.connecting:
            statusColor = Colors.orangeAccent;
            statusText = "Connecting...";
            break;
          default:
            statusColor = Colors.white54;
            statusText = "Ready (Deep Sleep)";
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: statusColor.withValues(alpha: 0.4),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              statusText,
              style: TextStyle(
                color: statusColor,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                fontFamily: GoogleFonts.lexend().fontFamily,
              ),
            ),
          ],
        );
      },
    );
  }
}
