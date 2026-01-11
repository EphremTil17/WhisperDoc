import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/services/hotkey_service.dart';
import 'package:flutter_client/core/services/logging_service.dart';
import 'package:flutter_client/core/services/settings_service.dart';
import 'package:flutter_client/ui/features/recording/recording.dart';
import 'package:flutter_client/ui/shared/widgets/custom_title_bar.dart';
import 'package:flutter_client/ui/shared/widgets/floating_capsule.dart';
import 'package:flutter_client/ui/shared/widgets/hamburger_menu.dart';
import 'package:flutter_client/ui/shared/widgets/refined_icon_button.dart';
import 'package:flutter_client/ui/shared/widgets/transcribed_text_area.dart';
import 'package:flutter_client/ui/shared/widgets/audio_visualizer.dart';
import 'package:flutter_client/ui/screens/settings_screen.dart';
import 'package:flutter_client/ui/screens/log_viewer_dialog.dart';
import 'package:flutter_client/ui/screens/history_dialog.dart';
import 'package:flutter_client/ui/theme/app_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  StreamSubscription? _hotkeySubscription;

  @override
  void initState() {
    super.initState();
    _initHotkeys();
  }

  void _initHotkeys() {
    final hotkeyService = context.read<HotkeyService>();
    final settings = context.read<SettingsService>();

    // Ensure controller is available
    final controller = context.read<RecordingController>();

    // Start with current settings
    // The new service automagically handles restarts if we call start() again
    unawaited(_restartHotkeyService(hotkeyService, settings));

    _hotkeySubscription = hotkeyService.onHotkeyPressed.listen((event) {
      LoggingService().info('Hotkey triggered - toggling recording');
      unawaited(controller.toggleRecording());
    });

    // Handle settings changes
    settings.addListener(_onSettingsChanged);
  }

  void _onSettingsChanged() {
    final hotkeyService = context.read<HotkeyService>();
    final settings = context.read<SettingsService>();

    // Simply restart the service with new settings
    // The service handles the "kill and respawn" logic internally
    unawaited(_restartHotkeyService(hotkeyService, settings));
  }

  Future<void> _restartHotkeyService(
    HotkeyService service,
    SettingsService settings,
  ) async {
    try {
      await service.start(
        id: 1,
        modifiers: settings.hotkeyModifiers,
        vKey: settings.hotkeyVKey,
      );
    } catch (e) {
      LoggingService().error('Failed to start/restart hotkey service: $e');
    }
  }

  void _toggleIncognitoMode(
    BuildContext context,
    RecordingController controller,
  ) {
    if (controller.incognitoMode) {
      // Turn OFF incognito - no confirmation needed
      controller.disableIncognitoMode();
    } else {
      // Turn ON incognito - show confirmation
      unawaited(
        showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1a1a2e),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            title: const Row(
              children: [
                Icon(
                  Icons.visibility_off,
                  color: Colors.orangeAccent,
                  size: 24,
                ),
                SizedBox(width: 12),
                Text(
                  'Enable Incognito Mode?',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
            content: const Text(
              'This will clear your current transcription history. '
              'New transcriptions will not be saved while incognito mode is active.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: TextButton.styleFrom(
                  backgroundColor: Colors.orangeAccent.withValues(alpha: 0.2),
                ),
                child: const Text(
                  'Enable',
                  style: TextStyle(color: Colors.orangeAccent),
                ),
              ),
            ],
          ),
        ).then((confirmed) {
          if (confirmed == true) {
            controller.enableIncognitoMode();
          }
        }),
      );
    }
  }

  @override
  void dispose() {
    context.read<SettingsService>().removeListener(_onSettingsChanged);
    unawaited(_hotkeySubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watch controller for UI updates
    final controller = context.watch<RecordingController>();
    final isRecording = controller.isRecording;

    return Scaffold(
      body: Container(
        decoration: AppTheme.mainGradient,
        child: Column(
          children: [
            const CustomTitleBar(),
            Expanded(
              child: Stack(
                children: [
                  const Positioned(top: 10, right: 24, child: HamburgerMenu()),
                  SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        children: [
                          const SizedBox(height: 16),
                          // Title Section
                          const Text(
                            'WhisperDoc',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -1.0,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'AI-Powered Speech-to-Text Dictation',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white54,
                            ),
                          ),

                          const SizedBox(height: 16),
                          FloatingCapsule(
                            isRecording: isRecording,
                            onTap: () =>
                                unawaited(controller.toggleRecording()),
                          ),

                          const SizedBox(height: 8),
                          if (isRecording) ...[
                            const AudioVisualizer(),
                            const SizedBox(height: 8),
                          ] else
                            const SizedBox(height: 8),

                          const HotkeyHint(),
                          const SizedBox(height: 12),
                          TranscribedTextArea(text: controller.currentText),

                          const SizedBox(height: 12),
                          // Footer: [Incognito] [History] • Connected [Settings] [Log]
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // LEFT SIDE - Incognito button
                              RefinedIconButton(
                                icon: controller.incognitoMode
                                    ? Icons.visibility_off
                                    : Icons.visibility_off_outlined,
                                iconColor: controller.incognitoMode
                                    ? Colors.orangeAccent
                                    : Colors.white38,
                                iconSize: 16,
                                onTap: () =>
                                    _toggleIncognitoMode(context, controller),
                              ),
                              const SizedBox(width: 8),
                              // History button
                              RefinedIconButton(
                                icon: Icons.history,
                                iconColor: Colors.white38,
                                iconSize: 16,
                                onTap: () {
                                  unawaited(
                                    showDialog(
                                      context: context,
                                      builder: (ctx) => const HistoryDialog(),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(width: 16),
                              // CENTER - Status
                              const StatusBar(),
                              const SizedBox(width: 16),
                              // RIGHT SIDE - Settings button (moved)
                              RefinedIconButton(
                                icon: Icons.settings_outlined,
                                iconColor: AppTheme.crimsonPrimary,
                                iconSize: 18,
                                onTap: () {
                                  unawaited(
                                    showDialog(
                                      context: context,
                                      builder: (ctx) => const SettingsScreen(),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(width: 8),
                              // Log button
                              RefinedIconButton(
                                icon: Icons.terminal_outlined,
                                iconColor: Colors.white38,
                                iconSize: 16,
                                onTap: () {
                                  unawaited(
                                    showDialog(
                                      context: context,
                                      builder: (ctx) => const LogViewerDialog(),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
