import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/ui/screens/home/dialogs/profile_hub_dialog.dart';
import 'package:flutter_client/controllers/profile_controller.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/services/transcription/groq_transcription_service.dart';

class ProfileHub extends StatefulWidget {
  const ProfileHub({super.key});

  @override
  State<ProfileHub> createState() => _ProfileHubState();
}

class _ProfileHubState extends State<ProfileHub>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();

    if (settings.isGroqMode) {
      return _buildGroqHub(context);
    }
    return _buildBackendHub(context);
  }

  Widget _buildGroqHub(BuildContext context) {
    final groqService = context.watch<GroqTranscriptionService>();
    final hasKey = groqService.hasValidCredentials;

    return Tooltip(
      message: hasKey ? 'Groq Cloud Profile' : 'Configure Groq Cloud',
      verticalOffset: 25,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            unawaited(
              showDialog(
                context: context,
                barrierColor: Colors.black.withValues(alpha: 0.7),
                builder: (context) => const ProfileHubDialog(),
              ),
            );
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: _isHovered
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _isHovered
                    ? Colors.white.withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.1),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: hasKey
                      ? Colors.greenAccent.withValues(alpha: 0.1)
                      : Colors.orangeAccent.withValues(alpha: 0.1),
                  child: Icon(
                    hasKey ? Icons.cloud_done : Icons.cloud_off,
                    size: 16,
                    color: hasKey ? Colors.greenAccent : Colors.orangeAccent,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.menu,
                  size: 20,
                  color: _isHovered
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackendHub(BuildContext context) {
    final profileController = context.watch<ProfileController>();
    final user = profileController.currentUser;
    final updateUI = profileController.updateUI;
    final isPulsing = updateUI.isPulsing;

    if (isPulsing && !_pulseController.isAnimating) {
      unawaited(_pulseController.repeat(reverse: true));
    } else if (!isPulsing && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.reset();
    }

    return Tooltip(
      message: 'Manage Profile',
      verticalOffset: 25,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            unawaited(
              showDialog(
                context: context,
                barrierColor: Colors.black.withValues(alpha: 0.7),
                builder: (context) => const ProfileHubDialog(),
              ),
            );
          },
          child: AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              final pulseVal = isPulsing ? _pulseAnimation.value : 0.0;
              final glowColor = updateUI.glowColor;

              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: _isHovered
                      ? Colors.white.withValues(alpha: 0.1)
                      : glowColor.withValues(
                          alpha: 0.05 + (pulseVal * 0.05),
                        ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _isHovered
                        ? Colors.white.withValues(alpha: 0.2)
                        : isPulsing
                            ? glowColor.withValues(
                                alpha: 0.15 + (pulseVal * 0.35),
                              )
                            : Colors.white.withValues(alpha: 0.1),
                    width: isPulsing ? 1.0 + (pulseVal * 0.5) : 1,
                  ),
                  boxShadow: _isHovered || isPulsing
                      ? [
                          BoxShadow(
                            color: isPulsing
                                ? glowColor.withValues(
                                    alpha: 0.2 * pulseVal,
                                  )
                                : Colors.black.withValues(alpha: 0.2),
                            blurRadius: isPulsing ? 10 * pulseVal : 10,
                            offset: isPulsing
                                ? Offset.zero
                                : const Offset(0, 4),
                            spreadRadius: isPulsing ? 2 * pulseVal : 0,
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (user?['picture'] != null)
                      CircleAvatar(
                        radius: 14,
                        backgroundImage: NetworkImage(
                          user!['picture'] as String,
                        ),
                      )
                    else
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: Colors.white.withValues(alpha: 0.1),
                        child: const Icon(
                          Icons.person,
                          size: 16,
                          color: Colors.white70,
                        ),
                      ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.menu,
                      size: 20,
                      color: _isHovered
                          ? Colors.white
                          : isPulsing
                              ? glowColor
                              : Colors.white.withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
