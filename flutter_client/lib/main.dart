import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'core/services/websocket_service.dart';
import 'core/services/audio_service.dart';
import 'core/services/hotkey_service.dart';
import 'core/services/settings_service.dart';
import 'ui/theme/app_theme.dart';
import 'ui/screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  // Window Options
  const WindowOptions windowOptions = WindowOptions(
    size: Size(450, 800),
    minimumSize: Size(350, 600),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    title: "WhisperDoc",
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  // Initialize Services
  final settingsService = SettingsService();
  await settingsService.load();

  final wsService = WebSocketService(settingsService);
  final audioService = AudioService();
  final hotkeyService = HotkeyService();

  // Initial connection - removed to avoid idle jitter
  // wsService.connect();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settingsService),
        ChangeNotifierProvider.value(value: wsService),
        ChangeNotifierProvider.value(value: audioService),
        Provider.value(value: hotkeyService),
      ],
      child: const WhisperDocApp(),
    ),
  );
}

class WhisperDocApp extends StatelessWidget {
  const WhisperDocApp({super.key});

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
