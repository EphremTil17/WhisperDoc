import 'package:flutter_client/services/utility/clipboard_service.dart';
import 'package:flutter_client/services/utility/logging_service.dart';
import 'package:flutter_client/services/utility/settings_service.dart';

/// Service responsible for handling automated actions after a transcription completes,
/// such as copying to clipboard or simulating paste.
class AutomationService {
  static const int _logPreviewLength = 20;

  final SettingsService _settingsService;

  AutomationService(this._settingsService);

  /// Executes configured automation actions for the given transcription.
  Future<void> runAutomation(String text) async {
    if (text.trim().isEmpty) return;

    // Redact transcript content from local logs during incognito to prevent
    // local trace leakage through the in-app log buffer.
    final preview = String.fromCharCodes(text.runes.take(_logPreviewLength));
    final logPreview = _settingsService.incognitoMode
        ? '[REDACTED]'
        : '"$preview..."';
    LoggingService().info(
      'AutomationService: Processing text $logPreview',
      sendToServer: false,
    );

    try {
      if (_settingsService.autoCopy) {
        await ClipboardService.copyToClipboard(text);

        if (_settingsService.autoPaste) {
          await ClipboardService.simulatePaste();
        }
      }
    } catch (e) {
      LoggingService().error('Automation failed: $e', sendToServer: false);
    }
  }
}
