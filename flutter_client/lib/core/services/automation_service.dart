import 'dart:async';
import 'package:flutter_client/core/models/transcription_entry.dart';
import 'package:flutter_client/core/services/clipboard_service.dart';
import 'package:flutter_client/core/services/logging_service.dart';
import 'package:flutter_client/core/services/settings_service.dart';

/// Service responsible for handling automated actions after a transcription completes,
/// such as copying to clipboard or simulating paste.
class AutomationService {
  final SettingsService _settingsService;

  AutomationService(this._settingsService);

  /// Executes configured automation actions for the given transcription.
  Future<void> runAutomation(TranscriptionEntry entry) async {
    if (entry.text.trim().isEmpty) return;

    LoggingService().info(
      'AutomationService: Processing entry "${entry.text.substring(0, entry.text.length.clamp(0, 20))}..."',
      sendToServer: false,
    );

    try {
      if (_settingsService.autoCopy) {
        await ClipboardService.copyToClipboard(entry.text);

        if (_settingsService.autoPaste) {
          await ClipboardService.simulatePaste();
        }
      }
    } catch (e) {
      LoggingService().error('Automation failed: $e', sendToServer: false);
      // Re-throw if caller needs to know, or handle here.
      // For background automation, logging is usually sufficient.
    }
  }
}
