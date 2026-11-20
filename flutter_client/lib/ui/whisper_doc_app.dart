import 'package:material_ui/material_ui.dart';
import 'package:flutter_client/infrastructure/di/app_providers.dart';
import 'package:flutter_client/infrastructure/di/service_locator.dart';
import 'package:flutter_client/infrastructure/theme/app_theme.dart';
import 'package:flutter_client/ui/screens/boot_screen.dart';
import 'package:flutter_client/ui/screens/home_screen.dart';

/// Root widget: renders the [BootScreen] immediately, then swaps in the full
/// app once [ServiceLocator.setup] completes.
///
/// Service setup (vault, settings, database, hotkeys) runs behind the boot
/// screen, so startup never shows a blank or frozen window, and a setup
/// failure is reported instead of hanging.
class WhisperDocApp extends StatefulWidget {
  const WhisperDocApp({super.key});

  @override
  State<WhisperDocApp> createState() => _WhisperDocAppState();
}

class _WhisperDocAppState extends State<WhisperDocApp> {
  final Future<void> _services = ServiceLocator.setup();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _services,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _materialApp(BootScreen(error: snapshot.error));
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return _materialApp(const BootScreen());
        }

        return AppProviders(child: _materialApp(const HomeScreen()));
      },
    );
  }

  static Widget _materialApp(Widget home) => MaterialApp(
    title: 'WhisperDoc',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.darkTheme,
    home: home,
  );
}
