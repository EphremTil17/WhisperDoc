import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/services/hardware/hotkey_service.dart';
import 'package:flutter_client/services/utility/logging_service.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/ui/features/recording/recording.dart';
import 'package:flutter_client/ui/shared/widgets/custom_title_bar.dart';
import 'package:flutter_client/ui/shared/widgets/profile_hub.dart';
import 'package:flutter_client/services/transport/websocket_service.dart';
import 'package:flutter_client/ui/shared/widgets/app_footer.dart';
import 'package:flutter_client/ui/shared/widgets/action_bar.dart';
import 'package:flutter_client/ui/screens/home/widgets/transcription_view.dart';
import 'package:flutter_client/ui/screens/home/widgets/home_header.dart';
import 'package:flutter_client/ui/screens/home/widgets/recording_view.dart';
import 'package:flutter_client/ui/screens/home/widgets/ban_overlay.dart';
import 'package:flutter_client/ui/screens/home/dialogs/auth_error_dialog.dart';
import 'package:flutter_client/ui/screens/home/dialogs/incognito_toggle_dialog.dart';
import 'package:flutter_client/infrastructure/theme/app_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const _snackBarWidth = 350.0;
  static const _snackBarShortSeconds = 1;
  static const _snackBarAlphaStrong = 0.9;
  static const _snackBarAlphaMedium = 0.8;

  StreamSubscription? _hotkeySubscription;
  StreamSubscription? _errorSubscription;
  SettingsService? _settings;
  int? _lastModifiers;
  int? _lastVKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initHotkeys();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!mounted) return;
      unawaited(context.read<RecordingController>().refreshHardwareStatus());
    }
  }

  void _initHotkeys() {
    final hotkeyService = context.read<HotkeyService>();
    final controller = context.read<RecordingController>();
    _settings = context.read<SettingsService>();

    _errorSubscription = controller.onError.listen((error) {
      if (!mounted) return;
      final lowerError = error.toLowerCase();

      // 1. Prioritize Ban Awareness (Overlay handles this)
      if (context.read<WebSocketService>().status == ConnectionStatus.banned ||
          lowerError.contains('ban')) {
        return;
      }

      // 2. Handle Update Errors
      if (lowerError.contains('update required')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Update Required. Redirecting...'),
            backgroundColor: AppTheme.crimsonPrimary.withValues(
              alpha: _snackBarAlphaStrong,
            ),
            behavior: SnackBarBehavior.floating,
            width: _snackBarWidth,
            duration: const Duration(seconds: _snackBarShortSeconds),
          ),
        );

        return;
      }

      // 3. Handle Auth Errors (Modular Dialog)
      if (error.contains('Authentication Failed') ||
          error.contains('AUTH_FAILED') ||
          error.contains('API Key Authentication failed')) {
        unawaited(
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AuthErrorDialog(error: error),
          ),
        );
      } else {
        // 4. Default: Ephemeral Notification
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error),
            backgroundColor: Colors.redAccent.withValues(
              alpha: _snackBarAlphaMedium,
            ),
            behavior: SnackBarBehavior.floating,
            width: _snackBarWidth,
            duration: const Duration(seconds: _snackBarShortSeconds),
          ),
        );
      }
    });

    _lastModifiers = _settings?.hotkeyModifiers;
    _lastVKey = _settings?.hotkeyVKey;
    unawaited(_restartHotkeyService(hotkeyService));

    _hotkeySubscription = hotkeyService.onHotkeyPressed.listen((event) {
      final action = controller.isRecording ? 'Stopping' : 'Starting';
      LoggingService().info('Hotkey: $action recording');
      unawaited(controller.toggleRecording());
    });

    _settings?.addListener(_onSettingsChanged);
  }

  void _onSettingsChanged() {
    final hotkeyService = context.read<HotkeyService>();

    if (_lastModifiers != _settings?.hotkeyModifiers ||
        _lastVKey != _settings?.hotkeyVKey) {
      _lastModifiers = _settings?.hotkeyModifiers;
      _lastVKey = _settings?.hotkeyVKey;
      unawaited(_restartHotkeyService(hotkeyService));
    }
  }

  Future<void> _restartHotkeyService(HotkeyService service) async {
    try {
      await service.start(
        id: 1,
        modifiers: _settings?.hotkeyModifiers ?? 0,
        vKey: _settings?.hotkeyVKey ?? 0,
      );
    } catch (e) {
      LoggingService().error('Failed to start/restart hotkey service: $e');
    }
  }

  Future<void> _toggleIncognitoMode(
    BuildContext context,
    RecordingController controller,
  ) async {
    if (controller.isRecording) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Finish recording before changing privacy mode',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.orangeAccent.withValues(
            alpha: _snackBarAlphaMedium,
          ),
          duration: const Duration(seconds: 2),
        ),
      );

      return;
    }

    if (controller.incognitoMode) {
      await controller.disableIncognitoMode();
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => const IncognitoToggleDialog(),
      );
      if (confirmed == true) {
        await controller.enableIncognitoMode();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _settings?.removeListener(_onSettingsChanged);
    unawaited(_hotkeySubscription?.cancel());
    unawaited(_errorSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                      const Positioned(top: 10, right: 24, child: ProfileHub()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          children: [
                            const HomeHeader(),
                            const RecordingView(),
                            const Expanded(child: TranscriptionView()),
                            Consumer<RecordingController>(
                              builder: (context, controller, child) =>
                                  ActionBar(
                                    isIncognitoMode: controller.incognitoMode,
                                    onIncognitoTap: () => unawaited(
                                      _toggleIncognitoMode(context, controller),
                                    ),
                                  ),
                            ),
                            const SizedBox(height: 12),
                            const StatusBar(),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const AppFooter(),
              ],
            ),
            const BanOverlay(),
          ],
        ),
      ),
    );
  }
}
