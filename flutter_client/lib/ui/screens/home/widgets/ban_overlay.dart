import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/services/transport/websocket_service.dart';
import 'package:flutter_client/ui/shared/widgets/ban_countdown_overlay.dart';

class BanOverlay extends StatelessWidget {
  const BanOverlay({super.key});

  static const double _scrimAlpha = 0.92;

  @override
  Widget build(BuildContext context) {
    return Consumer<WebSocketService>(
      builder: (context, wsService, child) {
        if (wsService.status != ConnectionStatus.banned) {
          return const SizedBox.shrink();
        }

        // Below the title bar, so the window can still be moved, minimized
        // and closed during a cooldown.
        return Positioned.fill(
          top: AppSizes.titleBar,
          child: Container(
            color: AppColors.ground.withValues(alpha: _scrimAlpha),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: BanCountdownOverlay(
              countdownStream: wsService.banState.cooldownStream,
              initialSeconds: wsService.banState.cooldownRemaining,
              onReconnect: () => unawaited(wsService.connect()),
            ),
          ),
        );
      },
    );
  }
}
