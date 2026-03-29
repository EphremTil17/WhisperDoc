import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_client/services/utility/history_service.dart';
import 'package:flutter_client/services/utility/automation_service.dart';
import 'package:flutter_client/services/utility/logging_service.dart';

/// Specialized logic for processing transcription results and managing history.
/// Follows "Separation of Concerns": Controller orchestrates, Processor executes logic.
class TranscriptionProcessor {
  final HistoryService _historyService;
  final AutomationService _automationService;

  TranscriptionProcessor(this._historyService, this._automationService);

  /// Processes raw websocket text into a buffer.
  String appendText(String currentBuffer, String newText) {
    if (newText.trim().isEmpty) return currentBuffer;

    return currentBuffer.isEmpty ? newText : '$currentBuffer $newText';
  }

  /// Finalizes a recording session by saving to history and running automation.
  Future<void> finalizeSession({
    required String text,
    required bool incognitoMode,
    required VoidCallback onHistoryUpdated,
  }) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) return;

    final timestamp = DateTime.now();

    try {
      if (!incognitoMode) {
        await _historyService.saveTranscription(
          text: cleanText,
          timestamp: timestamp,
        );
        onHistoryUpdated();
      }

      await _automationService.runAutomation(cleanText);
    } catch (e) {
      LoggingService().error(
        'TranscriptionProcessor: Failed to finalize session',
        error: e,
      );
    }
  }
}
