import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/services/transport/websocket_service.dart';
import 'package:flutter_client/services/hardware/audio_device_monitor.dart';
import 'package:flutter_client/services/hardware/audio_service.dart';
import 'package:flutter_client/services/hardware/hotkey_service.dart';
import 'package:flutter_client/services/utility/automation_service.dart';
import 'package:flutter_client/services/utility/history_service.dart';
import 'package:flutter_client/services/auth/auth_service.dart';
import 'package:flutter_client/services/auth/session_manager.dart';
import 'package:flutter_client/services/hardware/audio_cue_service.dart';
import 'package:flutter_client/services/utility/update_service.dart';
import 'package:flutter_client/services/transcription/cloud_http.dart';
import 'package:flutter_client/services/transcription/cloud_transcription_service.dart';
import 'package:flutter_client/services/transcription/groq_chat_engine.dart';
import 'package:flutter_client/services/transcription/groq_speech_engine.dart';
import 'package:flutter_client/services/transcription/open_router_catalog.dart';
import 'package:flutter_client/services/transcription/open_router_chat_engine.dart';
import 'package:flutter_client/services/transcription/open_router_speech_engine.dart';
import 'package:flutter_client/services/transcription/transform_service.dart';
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
    getIt.registerSingleton<AudioDeviceMonitor>(AudioDeviceMonitor()..start());

    final audioCueService = AudioCueService();
    final authService = AuthService(
      session: SessionManager(vault: settingsService.vault),
    );
    final historyService = HistoryService(settingsService.vault);

    // Run independent I/O initializers concurrently to trim startup latency.
    await Future.wait([
      audioCueService.initialize(),
      authService.initialize(),
      historyService.initialize(),
    ]);

    getIt.registerSingleton<AudioCueService>(audioCueService);
    getIt.registerSingleton<AuthService>(authService);

    // 3. Services with dependencies
    getIt.registerSingleton<WebSocketService>(
      WebSocketService(getIt<SettingsService>(), getIt<AuthService>()),
    );

    getIt.registerSingleton<AutomationService>(
      AutomationService(getIt<SettingsService>()),
    );

    getIt.registerSingleton<HistoryService>(historyService);

    getIt.registerSingleton<UpdateService>(
      UpdateService(getIt<WebSocketService>()),
    );

    // 3b. Cloud sources: one keep-alive connection pool for all of them.
    final cloudHttp = CloudHttp();
    final catalog = OpenRouterCatalog(settingsService, cloudHttp);
    getIt.registerSingleton<OpenRouterCatalog>(catalog);
    // The saved list loads in the background; startup never waits on it.
    unawaited(catalog.load());
    getIt.registerSingleton<CloudTranscriptionService>(
      CloudTranscriptionService(settingsService, [
        GroqSpeechEngine(settingsService, cloudHttp),
        OpenRouterSpeechEngine(settingsService, cloudHttp, catalog),
      ]),
    );
    // Registered on its own too: Account checks a rewrite model with it.
    final openRouterChat = OpenRouterChatEngine(settingsService, cloudHttp);
    getIt.registerSingleton<OpenRouterChatEngine>(openRouterChat);
    getIt.registerSingleton<TransformService>(
      TransformService(settingsService, [
        GroqChatEngine(settingsService, cloudHttp),
        openRouterChat,
      ]),
    );

    // 4. Controllers
    getIt.registerSingleton<RecordingController>(
      RecordingController(
        audioService: getIt<AudioService>(),
        wsService: getIt<WebSocketService>(),
        cloudService: getIt<CloudTranscriptionService>(),
        transformService: getIt<TransformService>(),
        automationService: getIt<AutomationService>(),
        historyService: getIt<HistoryService>(),
        settingsService: getIt<SettingsService>(),
        audioCueService: getIt<AudioCueService>(),
        deviceMonitor: getIt<AudioDeviceMonitor>(),
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
