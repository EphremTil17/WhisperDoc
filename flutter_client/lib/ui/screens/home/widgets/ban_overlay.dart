import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/services/transport/websocket_service.dart';
import 'package:flutter_client/ui/shared/widgets/ban_countdown_overlay.dart';

class BanOverlay extends StatelessWidget {
  const BanOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<WebSocketService>(
      builder: (context, wsService, child) {
        if (wsService.status != ConnectionStatus.banned) {
          return const SizedBox.shrink();
        }
        return Positioned.fill(
          child: Container(
            color: Colors.black87,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: BanCountdownOverlay(
              countdownStream: wsService.banState.cooldownStream,
              onReconnect: () => unawaited(wsService.connect()),
            ),
          ),
        );
      },
    );
  }
}
