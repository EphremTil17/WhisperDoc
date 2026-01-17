import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/services/hotkey_service.dart';
import 'package:flutter_client/core/services/logging_service.dart';
import 'package:flutter_client/core/services/settings_service.dart';
import 'package:flutter_client/core/services/websocket_service.dart';
import 'package:flutter_client/ui/features/recording/recording.dart';
import 'package:flutter_client/ui/shared/widgets/custom_title_bar.dart';
import 'package:flutter_client/ui/shared/widgets/hamburger_menu.dart';
import 'package:flutter_client/ui/shared/widgets/app_footer.dart';
import 'package:flutter_client/ui/shared/widgets/action_bar.dart';
import 'package:flutter_client/ui/shared/widgets/ban_countdown_overlay.dart';
import 'package:flutter_client/ui/screens/settings_screen.dart';
import 'package:flutter_client/ui/screens/home/widgets/home_header.dart';
import 'package:flutter_client/ui/screens/home/widgets/recording_view.dart';
import 'package:flutter_client/ui/screens/home/widgets/transcription_view.dart';
import 'package:flutter_client/ui/theme/app_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  StreamSubscription? _hotkeySubscription;
  StreamSubscription? _errorSubscription;
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

    // Listen for recording errors (Phase 8)
    _errorSubscription = controller.onError.listen((error) {
      if (!mounted) return;
      if (error.contains('Authentication Failed') ||
          error.contains('AUTH_FAILED')) {
        _showAuthErrorDialog(error);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error),
            backgroundColor: Colors.redAccent.withValues(alpha: 0.8),
            behavior: SnackBarBehavior.floating,
            width: 350,
          ),
        );
      }
    });

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
    // Block toggle during recording (Q3: Option A - Block Toggle)
    if (controller.isRecording) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Finish recording before changing privacy mode',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.orangeAccent.withValues(alpha: 0.8),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    if (controller.incognitoMode) {
      // Turn OFF incognito - no confirmation needed
      unawaited(controller.disableIncognitoMode());
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
              'This will permanently delete your local transcription history. '
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
            unawaited(controller.enableIncognitoMode());
          }
        }),
      );
    }
  }

  void _showAuthErrorDialog(String error) {
    unawaited(
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1a1a2e),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Colors.redAccent, width: 1),
          ),
          title: const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.redAccent),
              SizedBox(width: 12),
              Text(
                'Authentication Failed',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ],
          ),
          content: Text(
            '$error. Please verify your API Key or JWT Token in settings.',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text(
                'Close',
                style: TextStyle(color: Colors.white54),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                unawaited(
                  showDialog(
                    context: context,
                    builder: (context) => const SettingsScreen(),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
              ),
              child: const Text(
                'Verify Settings',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    context.read<SettingsService>().removeListener(_onSettingsChanged);
    unawaited(_hotkeySubscription?.cancel());
    unawaited(_errorSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watch controller for UI updates
    return Scaffold(
      body: Container(
        decoration: AppTheme.mainGradient,
        child: Stack(
          children: [
            Column(
              children: [
                const CustomTitleBar(),
                Expanded(
                  child: Stack(
                    children: [
                      const Positioned(
                        top: 10,
                        right: 24,
                        child: HamburgerMenu(),
                      ),
                      SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            children: [
                              const HomeHeader(),
                              const RecordingView(),
                              const TranscriptionView(),

                              // Footer: [Incognito] [History] • Connected [Settings] [Log]
                              Consumer<RecordingController>(
                                builder: (context, controller, child) =>
                                    ActionBar(
                                      isIncognitoMode: controller.incognitoMode,
                                      onIncognitoTap: () =>
                                          _toggleIncognitoMode(
                                            context,
                                            controller,
                                          ),
                                    ),
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

            // Ban Overlay (Phase 4)
            Consumer<WebSocketService>(
              builder: (context, wsService, child) {
                if (wsService.status != ConnectionStatus.banned) {
                  return const SizedBox.shrink();
                }
                return Positioned.fill(
                  child: Container(
                    color: Colors.black87,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: BanCountdownOverlay(
                      countdownStream: wsService.banState.cooldownStream,
                      onReconnect: () => unawaited(wsService.connect()),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
