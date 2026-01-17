import 'package:flutter/material.dart';
import 'package:flutter_client/core/services/transport_security_service.dart';

/// Connection security indicator showing transport layer security status.
///
/// Displays:
/// - Green lock: WSS (secure) connection
/// - Yellow warning: WS on private IP (local development)
/// - Red block: Connection blocked (WS on public IP)
///
/// Provides visual feedback to users about connection security.
class ConnectionSecurityIndicator extends StatelessWidget {
  final SecurityStatus securityStatus;
  final String? serverUri;

  const ConnectionSecurityIndicator({
    super.key,
    required this.securityStatus,
    this.serverUri,
  });

  IconData _getIcon() {
    switch (securityStatus) {
      case SecurityStatus.secure:
        return Icons.lock;
      case SecurityStatus.localDev:
        return Icons.warning_amber;
      case SecurityStatus.blocked:
        return Icons.block;
    }
  }

  Color _getColor() {
    switch (securityStatus) {
      case SecurityStatus.secure:
        return Colors.green;
      case SecurityStatus.localDev:
        return Colors.orange;
      case SecurityStatus.blocked:
        return Colors.red;
    }
  }

  String _getTooltip() {
    switch (securityStatus) {
      case SecurityStatus.secure:
        return 'Secure: End-to-end encrypted via WSS';
      case SecurityStatus.localDev:
        return 'Local: Connection allowed via WS on private network (RFC 1918)';
      case SecurityStatus.blocked:
        return 'Blocked: Unencrypted WS is prohibited on public networks';
    }
  }

  String _getLabel() {
    switch (securityStatus) {
      case SecurityStatus.secure:
        return 'Secure';
      case SecurityStatus.localDev:
        return 'Local';
      case SecurityStatus.blocked:
        return 'Blocked';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: _getTooltip(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _getColor().withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _getColor(), width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_getIcon(), color: _getColor(), size: 16),
            const SizedBox(width: 6),
            Text(
              _getLabel(),
              style: TextStyle(
                color: _getColor(),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
