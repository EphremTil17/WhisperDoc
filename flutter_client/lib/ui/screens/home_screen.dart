import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/services/hotkey_service.dart';
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
    // Note: Checking mounted before using context in async callbacks is good practice,
    // but here we are in initState.

    // Ensure controller is available
    final controller = context.read<RecordingController>();

    unawaited(
      hotkeyService.start().then((_) {
        if (!mounted) return;
        _registerCurrentHotkey(hotkeyService, settings);
      }),
    );

    _hotkeySubscription = hotkeyService.onHotkeyPressed.listen((event) {
      if (event == 1) {
        // 1 is our hotkey ID
        unawaited(controller.toggleRecording());
      }
    });

    // Handle hotkey changes from settings
    settings.addListener(_onSettingsChanged);
  }

  void _onSettingsChanged() {
    final hotkeyService = context.read<HotkeyService>();
    final settings = context.read<SettingsService>();

    _registerCurrentHotkey(hotkeyService, settings);
    // Note: Removed setState() - UI rebuilds via RecordingController.notifyListeners
    // and HotkeyHint watching SettingsService directly
  }

  void _registerCurrentHotkey(HotkeyService service, SettingsService settings) {
    unawaited(
      service.unregisterHotkey(1).then((_) {
        return service.registerHotkey(
          id: 1,
          modifiers: settings.hotkeyModifiers,
          vKey: settings.hotkeyVKey,
        );
      }),
    );
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
                          // Footer with Settings, Status, and Log viewer
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
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
                              const SizedBox(width: 16),
                              const StatusBar(),
                              const SizedBox(width: 16),
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
