import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_client/controllers/profile_controller.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/ui/screens/home/dialogs/profile_hub_dialog.dart';
import 'package:flutter_client/ui/shared/widgets/profile_hub_backend.dart';
import 'package:flutter_client/ui/shared/widgets/profile_hub_groq.dart';
import 'package:provider/provider.dart';

class ProfileHub extends StatefulWidget {
  const ProfileHub({super.key});

  @override
  State<ProfileHub> createState() => _ProfileHubState();
}

class _ProfileHubState extends State<ProfileHub>
    with SingleTickerProviderStateMixin {
  static const _pulseDuration = Duration(milliseconds: 1500);

  bool _isHovered = false;
  bool _isPulseActive = false;
  AnimationController? _pulseControllerValue;
  Animation<double>? _pulseAnimationValue;

  Animation<double> get _pulseAnimation {
    final pulseAnimation = _pulseAnimationValue;
    if (pulseAnimation == null) {
      throw StateError('ProfileHub pulse animation is not initialized.');
    }

    return pulseAnimation;
  }

  @override
  void initState() {
    super.initState();
    final pulseController = AnimationController(
      vsync: this,
      duration: _pulseDuration,
    );
    _pulseControllerValue = pulseController;
    _pulseAnimationValue = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: pulseController, curve: Curves.easeInOut),
    );
  }

  void _handleHoverChanged(bool isHovered) {
    if (_isHovered == isHovered) {
      return;
    }

    setState(() {
      _isHovered = isHovered;
    });
  }

  void _openProfileHubDialog() {
    unawaited(
      showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(
          alpha: ProfileHubGroq.overlayAlpha,
        ),
        builder: (context) => const ProfileHubDialog(),
      ),
    );
  }

  void _syncPulseAnimation(bool shouldPulse) {
    if (_isPulseActive == shouldPulse) {
      return;
    }

    _isPulseActive = shouldPulse;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      final pulseController = _pulseControllerValue;
      if (pulseController == null) {
        return;
      }

      if (shouldPulse) {
        if (!pulseController.isAnimating) {
          unawaited(pulseController.repeat(reverse: true));
        }

        return;
      }

      if (pulseController.isAnimating) {
        pulseController.stop();
      }
      if (pulseController.value != 0) {
        pulseController.reset();
      }
    });
  }

  @override
  void dispose() {
    _pulseControllerValue?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();

    if (settings.isGroqMode) {
      _syncPulseAnimation(false);

      return ProfileHubGroq(
        isHovered: _isHovered,
        onHoverChanged: _handleHoverChanged,
        onOpen: _openProfileHubDialog,
      );
    }

    final isPulsing = context.select<ProfileController, bool>(
      (controller) => controller.updateUI.isPulsing,
    );
    _syncPulseAnimation(isPulsing);

    return ProfileHubBackend(
      isHovered: _isHovered,
      pulseAnimation: _pulseAnimation,
      onHoverChanged: _handleHoverChanged,
      onOpen: _openProfileHubDialog,
    );
  }
}
