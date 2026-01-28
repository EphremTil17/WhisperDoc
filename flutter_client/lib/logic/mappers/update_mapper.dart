import 'package:flutter/material.dart';
import 'package:flutter_client/services/utility/update_service.dart';

class UpdateUIDescriptor {
  final Color glowColor;
  final bool isPulsing;
  final String label;

  const UpdateUIDescriptor({
    required this.glowColor,
    required this.isPulsing,
    required this.label,
  });
}

class UpdateMapper {
  static UpdateUIDescriptor map(UpdateStatus status) {
    switch (status) {
      case UpdateStatus.required:
        return const UpdateUIDescriptor(
          glowColor: Colors.redAccent,
          isPulsing: true,
          label: 'Critical Update Required',
        );
      case UpdateStatus.advisory:
        return const UpdateUIDescriptor(
          glowColor: Colors.orangeAccent,
          isPulsing: true,
          label: 'Update Available',
        );
      case UpdateStatus.upToDate:
        return const UpdateUIDescriptor(
          glowColor: Color(0xFF10B981), // Solid Emerald Green
          isPulsing: false,
          label: 'App is Up to Date',
        );
    }
  }
}
