import 'dart:async';

import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import 'package:flutter_client/services/transport/transport_security_service.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/ui/shared/widgets/panel/app_panel.dart';
import 'package:flutter_client/ui/shared/widgets/panel/choice_panel.dart';
import 'package:flutter_client/ui/shared/widgets/panel/field_panel.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// The connection values the Account panel edits, each on its own page.
/// Shared by the rows that open them and by flows that need one directly
/// (switching to Groq without a key opens [groqKey]).
abstract final class AccountFields {
  static const int _promptLines = 4;

  static Future<void> groqKey(BuildContext context) {
    final settings = context.read<SettingsService>();

    return AppPanel.push(
      context,
      FieldPanel(
        title: 'API key',
        label: 'Groq API key',
        initialValue: settings.cachedGroqApiKey ?? '',
        hint: 'gsk_…',
        note:
            'Create one free at console.groq.com. '
            'It is stored encrypted on this PC.',
        secret: true,
        validate: (value) => value.isEmpty ? 'Paste your key' : null,
        onSave: settings.setGroqApiKey,
      ),
    );
  }

  static Future<void> groqModel(BuildContext context) {
    final settings = context.read<SettingsService>();

    return AppPanel.push(
      context,
      ChoicePanel<String>(
        title: 'Model',
        options: [
          for (final model in AppConstants.groqSupportedModels)
            (model, AppConstants.groqModelDisplayNames[model] ?? model),
        ],
        selected: settings.groqModel,
        onSelected: (model) => unawaited(settings.setGroqModel(model)),
        note: 'Turbo is faster; Large v3 is slightly more accurate.',
      ),
    );
  }

  static Future<void> groqLanguage(BuildContext context) {
    final settings = context.read<SettingsService>();
    final byName = AppConstants.groqLanguageNames.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    return AppPanel.push(
      context,
      ChoicePanel<String>(
        title: 'Language',
        options: [
          ('', languageName('')),
          for (final MapEntry(key: code, value: name) in byName) (code, name),
        ],
        selected: settings.groqLanguage.toLowerCase(),
        onSelected: (code) => unawaited(settings.setGroqLanguage(code)),
        note:
            'Choosing the language you speak makes short clips more accurate.',
      ),
    );
  }

  /// The name shown for a stored language code; empty means auto-detect.
  static String languageName(String code) => code.isEmpty
      ? 'Auto-detect'
      : AppConstants.groqLanguageNames[code.toLowerCase()] ?? code;

  static Future<void> groqPrompt(BuildContext context) {
    final settings = context.read<SettingsService>();

    return AppPanel.push(
      context,
      FieldPanel(
        title: 'Words to expect',
        label: 'Names and terms',
        initialValue: settings.groqPrompt,
        hint: 'e.g. Kubernetes, Siobhan, WhisperDoc',
        note: 'Helps spell names and terms. Keep it short.',
        maxLines: _promptLines,
        onSave: settings.setGroqPrompt,
      ),
    );
  }

  static Future<void> server(BuildContext context) {
    final settings = context.read<SettingsService>();

    return AppPanel.push(
      context,
      FieldPanel(
        title: 'Server',
        label: 'Server address',
        initialValue: settings.serverUri,
        hint: 'ws://localhost:9989/ws',
        note: 'The WebSocket address of your WhisperDoc server.',
        validate: _webSocketProblem,
        onSave: settings.setServerUri,
      ),
    );
  }

  static Future<void> developerKey(BuildContext context) {
    final settings = context.read<SettingsService>();

    return AppPanel.push(
      context,
      FieldPanel(
        title: 'Developer key',
        label: 'API key',
        initialValue: settings.cachedApiKey ?? '',
        note: 'For servers without sign-in. Leave it empty to remove it.',
        secret: true,
        onSave: settings.setApiKey,
      ),
    );
  }

  /// Checks the address the connection will actually use: https:// becomes
  /// wss:// (the default server is stored as https://), http:// becomes
  /// ws://, and a bare host gets a scheme. ws:// stays local-only.
  static String? _webSocketProblem(String value) {
    final uri = Uri.tryParse(TransportSecurityService().normalizeUri(value));
    final isWebSocket =
        uri != null &&
        (uri.scheme == 'ws' || uri.scheme == 'wss') &&
        uri.host.isNotEmpty;
    if (!isWebSocket) return 'Use a wss:// or https:// address';
    if (uri.scheme == 'ws' &&
        !TransportSecurityService.isLocalOrPrivateHost(uri.host)) {
      return 'Use wss:// for remote servers (ws:// is local only)';
    }

    return null;
  }
}
