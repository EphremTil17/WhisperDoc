import 'package:flutter_client/services/utility/clipboard_service.dart';
import 'package:flutter_client/services/utility/logging_service.dart';
import 'package:flutter_client/services/utility/settings_service.dart';

/// Service responsible for handling automated actions after a transcription completes,
/// such as copying to clipboard or simulating paste.
class AutomationService {
  final LoggingService _logger = LoggingService();

  final SettingsService _settingsService;

  AutomationService(this._settingsService);

  /// Executes configured automation actions for the given transcription.
  Future<void> runAutomation(String text) async {
    if (text.trim().isEmpty) return;

    // Never log transcript plaintext into the in-app log buffer (which is
    // user-visible and copyable via LogsPanel).
    final summary = _settingsService.incognitoMode
        ? '[REDACTED]'
        : '(${text.length} chars)';
    _logger.info('AutomationService: Processing transcript $summary');

    try {
      if (_settingsService.autoCopy) {
        final copied = await ClipboardService.copyToClipboard(
          text,
          private: _settingsService.incognitoMode,
        );

        // Pasting after a failed copy would paste whatever the clipboard
        // already held (possibly a password), not the transcription.
        if (copied && _settingsService.autoPaste) {
          await ClipboardService.simulatePaste();
        }
      }
    } catch (e) {
      _logger.error('Automation failed: $e');
    }
  }
}
