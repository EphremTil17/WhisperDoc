import 'package:flutter_client/ui/screens/account/open_router_model_panel.dart';
import 'package:flutter_client/ui/screens/account_panel.dart';
import 'package:flutter_client/ui/screens/history_panel.dart';
import 'package:flutter_client/ui/screens/settings_panel.dart';
import 'package:flutter_client/ui/shared/widgets/panel/app_panel.dart';
import 'package:material_ui/material_ui.dart';

/// The home screen's destinations, opened from one place so the title bar,
/// stage and bottom bar do not each carry their own copy. Each is a
/// full-window panel with a back button.
abstract final class HomeNavigation {
  /// Connection, identity, updates and diagnostics.
  static Future<void> openAccount(BuildContext context) =>
      AppPanel.push<void>(context, const AccountPanel());

  /// How the app behaves: microphone, shortcut, what happens on stop.
  static Future<void> openSettings(BuildContext context) =>
      AppPanel.push<void>(context, const SettingsPanel());

  static Future<void> openHistory(BuildContext context) =>
      AppPanel.push<void>(context, const HistoryPanel());

  /// OpenRouter's models, straight from a "choose a model" prompt: picking
  /// one comes back here, ready to dictate.
  static Future<void> chooseModel(BuildContext context) =>
      AppPanel.push<void>(context, const OpenRouterModelPanel());
}
