import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/services/hardware/hotkey_service.dart';
import 'package:flutter_client/services/utility/logging_service.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/controllers/recording_controller.dart';
import 'package:flutter_client/services/transport/websocket_service.dart';
import 'package:flutter_client/ui/screens/home/dialogs/auth_error_dialog.dart';
import 'package:flutter_client/ui/screens/home/dialogs/incognito_toggle_dialog.dart';
import 'package:flutter_client/ui/screens/home/widgets/account_indicator.dart';
import 'package:flutter_client/ui/screens/home/widgets/ban_overlay.dart';
import 'package:flutter_client/ui/screens/home/widgets/home_bottom_bar.dart';
import 'package:flutter_client/ui/screens/home/widgets/home_stage.dart';
import 'package:flutter_client/ui/shared/widgets/custom_title_bar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const _briefNotice = Duration(seconds: 1);
  static const _notice = Duration(seconds: 2);

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
      if (context.read<WebSocketService>().status == ConnectionStatus.banned) {
        return;
      }

      // 2. Handle Update Errors
      if (lowerError.contains('update required')) {
        _notify('Update required. Redirecting…', _briefNotice);

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
        _notify(error, _briefNotice);
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

  /// One look for every notice (set by the snackbar theme).
  void _notify(String message, Duration duration) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: duration),
    );
  }

  Future<void> _toggleIncognitoMode(
    BuildContext context,
    RecordingController controller,
  ) async {
    if (controller.isRecording) {
      if (!mounted) return;
      _notify('Finish recording before changing privacy mode', _notice);

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
      body: Stack(
        children: [
          Column(
            children: [
              const CustomTitleBar(trailing: AccountIndicator()),
              const Expanded(child: HomeStage()),
              HomeBottomBar(
                onIncognitoTap: () => unawaited(
                  _toggleIncognitoMode(
                    context,
                    context.read<RecordingController>(),
                  ),
                ),
              ),
            ],
          ),
          const BanOverlay(),
        ],
      ),
    );
  }
}
