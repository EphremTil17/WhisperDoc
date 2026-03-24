import 'package:flutter/material.dart';
import 'package:flutter_client/services/transport/websocket_service.dart';
import 'package:flutter_client/services/transport/handshake_state_machine.dart';
import 'package:flutter_client/services/transport/transport_security_service.dart';
import 'package:flutter_client/services/transcription/groq_transcription_service.dart';
import 'package:flutter_client/infrastructure/theme/app_theme.dart';
import 'package:flutter_client/services/utility/update_service.dart';

/// Descriptor for how the connection UI should look and behave.
class ConnectionUIDescriptor {
  final IconData icon;
  final Color iconColor;
  final String tooltip;
  final bool isPulsing;
  final Color? pulseColor;

  const ConnectionUIDescriptor({
    required this.icon,
    required this.iconColor,
    required this.tooltip,
    this.isPulsing = false,
    this.pulseColor,
  });
}

/// Pure logic class to map service states to UI descriptors.
/// Adheres to "Agnostic Components" rule: UI doesn't know "why", it just knows "what".
class ConnectionStateMapper {
  static ConnectionUIDescriptor mapState({
    required ConnectionStatus status,
    required HandshakeState handshake,
    required SecurityStatus security,
    required bool hasAnyCreds,
    required UpdateStatus updateStatus,
  }) {
    IconData iconData = Icons.lock_outline;
    Color iconColor;
    String tooltipMsg;

    final bool isDisconnected = status == ConnectionStatus.disconnected;

    // Traffic Light Pulsing Logic
    bool shouldPulse = isDisconnected;
    Color pulseColor = hasAnyCreds ? Colors.greenAccent : Colors.orangeAccent;

    if (updateStatus == UpdateStatus.required) {
      pulseColor = AppTheme.crimsonPrimary;
      shouldPulse = true;
    } else if (updateStatus == UpdateStatus.advisory && isDisconnected) {
      pulseColor = Colors.orangeAccent;
      shouldPulse = true;
    }

    // Determine Icon and Color
    if (updateStatus == UpdateStatus.required) {
      iconColor = AppTheme.crimsonPrimary;
      iconData = Icons.system_update;
    } else if (handshake == HandshakeState.failed) {
      iconColor = AppTheme.crimsonPrimary;
      iconData = Icons.lock_open;
    } else if (status == ConnectionStatus.connected) {
      if (security == SecurityStatus.secure) {
        iconColor = Colors.greenAccent.withValues(alpha: 0.4);
        iconData = Icons.lock;
      } else {
        iconColor = Colors.orangeAccent.withValues(alpha: 0.4);
        iconData = Icons.lock_open;
      }
    } else if (status == ConnectionStatus.connecting) {
      iconColor = Colors.orangeAccent.withValues(alpha: 0.6);
    } else if (status == ConnectionStatus.banned) {
      iconColor = AppTheme.crimsonPrimary;
      iconData = Icons.block;
    } else {
      iconColor = AppTheme.crimsonPrimary.withValues(alpha: 0.4);
    }

    // Determine Tooltip
    if (updateStatus == UpdateStatus.required) {
      tooltipMsg = 'Critical Update Required. Click to Update.';
    } else if (status == ConnectionStatus.connected) {
      tooltipMsg = security == SecurityStatus.secure
          ? 'Securely Connected'
          : 'Connected (Unencrypted)';
    } else if (status == ConnectionStatus.connecting) {
      tooltipMsg = 'Connecting to Server...';
    } else if (status == ConnectionStatus.banned) {
      tooltipMsg = 'Access Denied (Banned)';
    } else if (updateStatus == UpdateStatus.advisory && isDisconnected) {
      tooltipMsg = 'Update Available. Recommended for Security.';
    } else if (isDisconnected && hasAnyCreds) {
      tooltipMsg = 'Identity Verified. Click to Connect.';
    } else if (isDisconnected && !hasAnyCreds) {
      tooltipMsg = 'Authentication Required. Click to Setup.';
    } else {
      tooltipMsg = 'Disconnected. Click to Connect.';
    }

    return ConnectionUIDescriptor(
      icon: iconData,
      iconColor: iconColor,
      tooltip: tooltipMsg,
      isPulsing: shouldPulse,
      pulseColor: pulseColor,
    );
  }

  /// Maps Groq Cloud engine state to a UI descriptor.
  ///
  /// Called instead of [mapState] when the app is in Groq mode.
  static ConnectionUIDescriptor mapGroqState({
    required bool hasGroqKey,
    required GroqTranscriptionStatus status,
  }) {
    switch (status) {
      case GroqTranscriptionStatus.buffering:
        return ConnectionUIDescriptor(
          icon: Icons.cloud_upload,
          iconColor: Colors.greenAccent.withValues(alpha: 0.8),
          tooltip: 'Recording (Groq Cloud)',
        );
      case GroqTranscriptionStatus.transcribing:
        return ConnectionUIDescriptor(
          icon: Icons.cloud_sync,
          iconColor: Colors.greenAccent.withValues(alpha: 0.8),
          tooltip: 'Transcribing via Groq...',
          isPulsing: true,
          pulseColor: Colors.greenAccent,
        );
      case GroqTranscriptionStatus.error:
        return const ConnectionUIDescriptor(
          icon: Icons.cloud_off,
          iconColor: AppTheme.crimsonPrimary,
          tooltip: 'Groq Cloud Error',
        );
      case GroqTranscriptionStatus.idle:
        if (hasGroqKey) {
          return ConnectionUIDescriptor(
            icon: Icons.cloud_done,
            iconColor: Colors.greenAccent.withValues(alpha: 0.8),
            tooltip: 'Groq Cloud (Ready)',
          );
        }
        return const ConnectionUIDescriptor(
          icon: Icons.cloud_off,
          iconColor: Colors.orangeAccent,
          tooltip: 'Groq Cloud — API Key Required',
          isPulsing: true,
          pulseColor: Colors.orangeAccent,
        );
    }
  }
}
