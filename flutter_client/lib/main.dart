import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_client/infrastructure/di/service_locator.dart';
import 'package:flutter_client/services/hardware/audio_service.dart';
import 'package:flutter_client/services/transport/websocket_service.dart';
import 'package:flutter_client/services/utility/automation_service.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/services/auth/auth_service.dart';
import 'package:flutter_client/services/hardware/hotkey_service.dart';
import 'package:flutter_client/services/hardware/audio_cue_service.dart';
import 'package:flutter_client/controllers/recording_controller.dart';
import 'package:flutter_client/infrastructure/theme/app_theme.dart';
import 'package:flutter_client/ui/screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Window Configuration & Service Initialization
  try {
    await windowManager.ensureInitialized();

    const windowOptions = WindowOptions(
      size: Size(420, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      title: "WhisperDoc",
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
      await windowManager.setResizable(false);
    });

    // Initialize all services via Service Locator
    await setupServices();
  } catch (e) {
    debugPrint('Critical Startup Error: $e');
  }

  runApp(
    MultiProvider(
      providers: [
        // Expose services to widget tree via Provider (for context.read/watch)
        ChangeNotifierProvider.value(value: getIt<SettingsService>()),
        ChangeNotifierProvider.value(value: getIt<WebSocketService>()),
        ChangeNotifierProvider.value(value: getIt<AudioService>()),
        ChangeNotifierProvider.value(value: getIt<AuthService>()),
        ChangeNotifierProvider.value(value: getIt<RecordingController>()),
        Provider.value(value: getIt<HotkeyService>()),
        Provider.value(value: getIt<AutomationService>()),
      ],
      child: const WhisperDocApp(),
    ),
  );
}

class WhisperDocApp extends StatefulWidget {
  const WhisperDocApp({super.key});

  @override
  State<WhisperDocApp> createState() => _WhisperDocAppState();
}

class _WhisperDocAppState extends State<WhisperDocApp> with WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  /// Called when user closes the window - cleanup all services
  @override
  Future<void> onWindowClose() async {
    // Stop hotkey service (kills the isolate)
    await getIt<HotkeyService>().stop();

    // Stop audio recording if active
    final audioService = getIt<AudioService>();
    if (audioService.isRecording) {
      await audioService.stopRecording();
    }

    // Close WebSocket connection
    await getIt<WebSocketService>().disconnect(reason: 'App closure');

    // Cleanup native audio memory
    getIt<AudioCueService>().dispose();

    // Allow window to close
    await windowManager.destroy();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WhisperDoc',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const HomeScreen(),
    );
  }
}
