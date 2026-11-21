import 'package:material_ui/material_ui.dart';
import 'package:flutter_client/ui/screens/home/dialogs/history_dialog.dart';
import 'package:flutter_client/ui/screens/home/dialogs/log_viewer_dialog.dart';
import 'package:flutter_client/ui/screens/home/dialogs/profile_hub_dialog.dart';
import 'package:flutter_client/ui/screens/settings_screen.dart';

/// The home screen's destinations, opened from one place so the title bar,
/// stage, bottom bar and account dialog do not each carry their own copy.
abstract final class HomeNavigation {
  static const double _accountBarrierAlpha = 0.7;

  /// Connection, identity, updates and diagnostics.
  static Future<void> openAccount(BuildContext context) => showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: _accountBarrierAlpha),
    builder: (_) => const ProfileHubDialog(),
  );

  /// How the app behaves: microphone, shortcut, output, automation.
  static Future<void> openSettings(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => const SettingsScreen(),
  );

  static Future<void> openHistory(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => const HistoryDialog(),
  );

  static Future<void> openLogs(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => const LogViewerDialog(),
  );
}
