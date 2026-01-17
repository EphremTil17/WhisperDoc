import 'package:get_it/get_it.dart';
import 'package:flutter_client/core/services/settings_service.dart';
import 'package:flutter_client/core/services/websocket_service.dart';
import 'package:flutter_client/core/services/audio_service.dart';
import 'package:flutter_client/core/services/hotkey_service.dart';
import 'package:flutter_client/core/services/automation_service.dart';
import 'package:flutter_client/core/services/history_service.dart';
import 'package:flutter_client/core/controllers/recording_controller.dart';

/// Global service locator instance.
final GetIt getIt = GetIt.instance;

/// Initializes and registers all application services.
///
/// Call this once at app startup before runApp().
Future<void> setupServices() async {
  // 1. Settings (must load first as other services depend on it)
  final settingsService = SettingsService();
  await settingsService.load();
  getIt.registerSingleton<SettingsService>(settingsService);

  // 2. Core Services
  getIt.registerSingleton<HotkeyService>(HotkeyService());
  getIt.registerSingleton<AudioService>(AudioService());

  // 3. Services with dependencies
  getIt.registerSingleton<WebSocketService>(
    WebSocketService(getIt<SettingsService>()),
  );

  getIt.registerSingleton<AutomationService>(
    AutomationService(getIt<SettingsService>()),
  );

  final historyService = HistoryService(getIt<SettingsService>().vault);
  await historyService.initialize();
  getIt.registerSingleton<HistoryService>(historyService);

  // 4. Controllers
  getIt.registerSingleton<RecordingController>(
    RecordingController(
      audioService: getIt<AudioService>(),
      wsService: getIt<WebSocketService>(),
      automationService: getIt<AutomationService>(),
      historyService: getIt<HistoryService>(),
      settingsService: getIt<SettingsService>(),
    ),
  );
}
