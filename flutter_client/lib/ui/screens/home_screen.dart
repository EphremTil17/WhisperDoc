import 'dart:async';
import 'dart:ui';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/services/hardware/hotkey_service.dart';
import 'package:flutter_client/services/utility/logging_service.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/controllers/recording_controller.dart';
import 'package:flutter_client/services/transport/websocket_service.dart';
import 'package:flutter_client/ui/screens/home/widgets/account_indicator.dart';
import 'package:flutter_client/ui/screens/home/widgets/ban_overlay.dart';
import 'package:flutter_client/ui/screens/home/widgets/home_bottom_bar.dart';
import 'package:flutter_client/ui/screens/home/widgets/home_stage.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/ui/shared/widgets/confirm_dialog.dart';
import 'package:flutter_client/ui/shared/widgets/crisp_text.dart';
import 'package:flutter_client/ui/shared/widgets/custom_title_bar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const _notice = Duration(seconds: 2);

  /// Errors can run to a sentence or two; give them time to be read.
  static const _errorNotice = Duration(seconds: 4);

  StreamSubscription? _hotkeySubscription;
  AppLifecycleListener? _lifecycle;
  StreamSubscription? _errorSubscription;
  SettingsService? _settings;
  int? _lastModifiers;
  int? _lastVKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lifecycle = AppLifecycleListener(onExitRequested: _onExitRequested);
    _initHotkeys();
  }

  /// Every way of closing (title-bar button, Alt+F4, taskbar) arrives here.
  /// The hotkey isolate blocks in a native GetMessageW call that the VM cannot
  /// interrupt, so it must be woken (WM_QUIT) before the engine shuts down;
  /// otherwise the window disappears but the process never exits.
  Future<AppExitResponse> _onExitRequested() async {
    await context.read<HotkeyService>().stop();

    return AppExitResponse.exit;
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

    // Sign-in, update and server problems show on the home stage itself, so
    // errors here are only notices. Their text may quote the server, so it
    // never decides what happens next.
    _errorSubscription = controller.onError.listen((error) {
      if (!mounted) return;
      // The ban overlay already explains a ban.
      if (context.read<WebSocketService>().status == ConnectionStatus.banned) {
        return;
      }
      _notify(error, _errorNotice);
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
      SnackBar(
        content: CrispText(message, style: AppType.caption),
        duration: duration,
      ),
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
      final confirmed = await ConfirmDialog.ask(
        context,
        title: 'Turn on incognito?',
        message:
            'This permanently deletes your local transcription history. '
            'Nothing new is saved while incognito is on.',
        confirmLabel: 'Turn on',
      );
      if (confirmed) {
        await controller.enableIncognitoMode();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lifecycle?.dispose();
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
