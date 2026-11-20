import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/controllers/profile_controller.dart';
import 'package:flutter_client/controllers/recording_controller.dart';
import 'package:flutter_client/infrastructure/di/service_locator.dart';
import 'package:flutter_client/services/auth/auth_service.dart';
import 'package:flutter_client/services/hardware/audio_service.dart';
import 'package:flutter_client/services/hardware/hotkey_service.dart';
import 'package:flutter_client/services/transcription/groq_transcription_service.dart';
import 'package:flutter_client/services/transport/websocket_service.dart';
import 'package:flutter_client/services/utility/automation_service.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/services/utility/update_service.dart';

/// Exposes [ServiceLocator] singletons to the widget tree.
///
/// Must sit above `MaterialApp` so dialogs and pushed routes can read them.
/// Only valid after [ServiceLocator.setup] has completed.
class AppProviders extends StatelessWidget {
  final Widget child;

  const AppProviders({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final getIt = ServiceLocator.getIt;

    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: getIt<SettingsService>()),
        ChangeNotifierProvider.value(value: getIt<WebSocketService>()),
        ChangeNotifierProvider.value(value: getIt<AudioService>()),
        ChangeNotifierProvider.value(value: getIt<AuthService>()),
        ChangeNotifierProvider.value(value: getIt<GroqTranscriptionService>()),
        ChangeNotifierProvider.value(value: getIt<RecordingController>()),
        Provider.value(value: getIt<HotkeyService>()),
        Provider.value(value: getIt<AutomationService>()),
        ChangeNotifierProvider.value(value: getIt<ProfileController>()),
        ChangeNotifierProvider.value(value: getIt<UpdateService>()),
      ],
      child: child,
    );
  }
}
