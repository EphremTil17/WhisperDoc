import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_client/infrastructure/theme/app_theme.dart';
import 'package:flutter_client/logic/mappers/connection_ui_map.dart';
import 'package:flutter_client/services/transport/websocket_service.dart';
import 'package:flutter_client/services/transport/handshake_state_machine.dart';
import 'package:flutter_client/services/transport/transport_security_service.dart';
import 'package:flutter_client/services/utility/update_service.dart';

void main() {
  group('ConnectionStateMapper', () {
    test('Maps required update to Red Pulse and Update Icon', () {
      final descriptor = ConnectionStateMapper.mapState(
        status: ConnectionStatus.disconnected,
        handshake: HandshakeState.locked,
        security: SecurityStatus.blocked,
        hasAnyCreds: true,
        updateStatus: UpdateStatus.required,
      );

      expect(descriptor.icon, Icons.system_update);
      expect(descriptor.isPulsing, true);
      expect(descriptor.pulseColor, AppTheme.crimsonPrimary);
      expect(descriptor.tooltip, contains('Critical Update'));
    });

    test('Maps advisory update to Amber Pulse when disconnected', () {
      final descriptor = ConnectionStateMapper.mapState(
        status: ConnectionStatus.disconnected,
        handshake: HandshakeState.locked,
        security: SecurityStatus.blocked,
        hasAnyCreds: true,
        updateStatus: UpdateStatus.advisory,
      );

      expect(descriptor.pulseColor, Colors.orangeAccent);
      expect(descriptor.tooltip, contains('Update Available'));
    });

    test('Maps disconnected state with valid credentials (Green Pulse)', () {
      final descriptor = ConnectionStateMapper.mapState(
        status: ConnectionStatus.disconnected,
        handshake: HandshakeState.locked,
        security: SecurityStatus.blocked,
        hasAnyCreds: true,
        updateStatus: UpdateStatus.upToDate,
      );

      expect(descriptor.isPulsing, true);
      expect(descriptor.pulseColor, Colors.greenAccent);
    });
  });
}
