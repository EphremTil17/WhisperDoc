import 'package:get_it/get_it.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/services/transport/websocket_service.dart';
import 'package:flutter_client/services/hardware/audio_service.dart';
import 'package:flutter_client/services/hardware/hotkey_service.dart';
import 'package:flutter_client/services/utility/automation_service.dart';
import 'package:flutter_client/services/utility/history_service.dart';
import 'package:flutter_client/services/auth/auth_service.dart';
import 'package:flutter_client/services/hardware/audio_cue_service.dart';
import 'package:flutter_client/services/utility/update_service.dart';
import 'package:flutter_client/services/transcription/groq_transcription_service.dart';
import 'package:flutter_client/services/transcription/groq_transform_service.dart';
import 'package:flutter_client/controllers/recording_controller.dart';
import 'package:flutter_client/controllers/profile_controller.dart';

/// Centralised service locator — wraps [GetIt] and owns app-startup wiring.
class ServiceLocator {
  /// Global [GetIt] instance shared across the app.
  static final GetIt getIt = GetIt.instance;

  /// Initializes and registers all application services.
  ///
  /// Call this once at app startup before runApp().
  static Future<void> setup() async {
    // 1. Settings (must load first as other services depend on it)
    final settingsService = SettingsService();
    await settingsService.load();
    getIt.registerSingleton<SettingsService>(settingsService);

    // 2. Core Services
    getIt.registerSingleton<HotkeyService>(HotkeyService());
    getIt.registerSingleton<AudioService>(AudioService());

    final audioCueService = AudioCueService();
    await audioCueService.initialize();
    getIt.registerSingleton<AudioCueService>(audioCueService);

    final authService = AuthService();
    await authService.initialize();
    getIt.registerSingleton<AuthService>(authService);

    // 3. Services with dependencies
    getIt.registerSingleton<WebSocketService>(
      WebSocketService(getIt<SettingsService>(), getIt<AuthService>()),
    );

    getIt.registerSingleton<AutomationService>(
      AutomationService(getIt<SettingsService>()),
    );

    final historyService = HistoryService(getIt<SettingsService>().vault);
    await historyService.initialize();
    getIt.registerSingleton<HistoryService>(historyService);

    getIt.registerSingleton<UpdateService>(
      UpdateService(getIt<WebSocketService>()),
    );

    // 3b. Groq Cloud Engine
    getIt.registerSingleton<GroqTranscriptionService>(
      GroqTranscriptionService(getIt<SettingsService>()),
    );
    getIt.registerSingleton<GroqTransformService>(
      GroqTransformService(getIt<SettingsService>()),
    );

    // 4. Controllers
    getIt.registerSingleton<RecordingController>(
      RecordingController(
        audioService: getIt<AudioService>(),
        wsService: getIt<WebSocketService>(),
        groqService: getIt<GroqTranscriptionService>(),
        transformService: getIt<GroqTransformService>(),
        automationService: getIt<AutomationService>(),
        historyService: getIt<HistoryService>(),
        settingsService: getIt<SettingsService>(),
        audioCueService: getIt<AudioCueService>(),
      ),
    );
    getIt.registerSingleton<ProfileController>(
      ProfileController(
        authService: getIt<AuthService>(),
        updateService: getIt<UpdateService>(),
      ),
    );
  }
}
