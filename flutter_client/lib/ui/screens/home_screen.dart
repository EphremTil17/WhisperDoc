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
import 'package:flutter_client/ui/shared/widgets/transcribed_text_area.dart';
import 'package:flutter_client/ui/shared/widgets/audio_visualizer.dart';
import 'package:flutter_client/ui/shared/widgets/app_footer.dart';
import 'package:flutter_client/ui/shared/widgets/action_bar.dart';
import 'package:flutter_client/ui/theme/app_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  StreamSubscription? _hotkeySubscription;
  int? _lastModifiers;
  int? _lastVKey;

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

    // Track initial hotkey settings to detect changes later
    _lastModifiers = settings.hotkeyModifiers;
    _lastVKey = settings.hotkeyVKey;

    // Start with current settings
    unawaited(_restartHotkeyService(hotkeyService, settings));

    _hotkeySubscription = hotkeyService.onHotkeyPressed.listen((event) {
      final action = controller.isRecording ? 'Stopping' : 'Starting';
      LoggingService().info('Hotkey: $action recording');
      unawaited(controller.toggleRecording());
    });

    // Handle settings changes
    settings.addListener(_onSettingsChanged);
  }

  void _onSettingsChanged() {
    final hotkeyService = context.read<HotkeyService>();
    final settings = context.read<SettingsService>();

    // Only restart hotkey service if hotkey settings actually changed
    if (_lastModifiers != settings.hotkeyModifiers ||
        _lastVKey != settings.hotkeyVKey) {
      _lastModifiers = settings.hotkeyModifiers;
      _lastVKey = settings.hotkeyVKey;
      unawaited(_restartHotkeyService(hotkeyService, settings));
    }
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
    final settings = context.watch<SettingsService>();
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
                          // Visualizer toggle for performance testing
                          if (settings.showVisualizer)
                            AnimatedOpacity(
                              opacity: isRecording ? 1.0 : 0.0,
                              duration: const Duration(milliseconds: 200),
                              child: const AudioVisualizer(),
                            )
                          else
                            const SizedBox(height: 40), // Placeholder height
                          const SizedBox(height: 8),

                          const HotkeyHint(),
                          const SizedBox(height: 12),
                          TranscribedTextArea(text: controller.currentText),

                          const SizedBox(height: 12),
                          // Footer: [Incognito] [History] • Connected [Settings] [Log]
                          ActionBar(
                            isIncognitoMode: controller.incognitoMode,
                            onIncognitoTap: () =>
                                _toggleIncognitoMode(context, controller),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Fixed Footer at bottom
            const AppFooter(),
          ],
        ),
      ),
    );
  }
}
