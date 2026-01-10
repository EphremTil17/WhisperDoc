import 'package:flutter/material.dart';
import 'package:flutter_client/core/models/transcription_entry.dart';
import 'package:flutter_client/ui/features/recording/recording_controller.dart';
import 'package:flutter_client/ui/theme/app_theme.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

class HistoryDialog extends StatelessWidget {
  const HistoryDialog({super.key});

  String _formatTimestamp(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<RecordingController>();
    final history = controller.history;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        decoration: AppTheme.glassDecoration.copyWith(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        'Transcription History',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          fontFamily: GoogleFonts.lexend().fontFamily,
                        ),
                      ),
                      if (controller.incognitoMode) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orangeAccent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'INCOGNITO',
                            style: TextStyle(
                              color: Colors.orangeAccent,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white54,
                      size: 18,
                    ),
                    splashRadius: 16,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            // History entries
            Expanded(
              child: history.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            controller.incognitoMode
                                ? Icons.visibility_off
                                : Icons.history,
                            color: Colors.white24,
                            size: 48,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            controller.incognitoMode
                                ? 'Incognito mode active\nHistory is disabled'
                                : 'No transcriptions yet',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 12,
                              fontFamily: GoogleFonts.lexend().fontFamily,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: history.length,
                      itemBuilder: (context, index) {
                        final entry = history[index];
                        return _HistoryEntryTile(
                          entry: entry,
                          timestamp: _formatTimestamp(entry.timestamp),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryEntryTile extends StatelessWidget {
  final TranscriptionEntry entry;
  final String timestamp;

  const _HistoryEntryTile({required this.entry, required this.timestamp});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timestamp
          Text(
            timestamp,
            style: TextStyle(
              color: Colors.white38,
              fontSize: 10,
              fontFamily: GoogleFonts.jetBrainsMono().fontFamily,
            ),
          ),
          const SizedBox(height: 6),
          // Transcription text
          SelectableText(
            entry.text,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              height: 1.4,
              fontFamily: GoogleFonts.lexend().fontFamily,
            ),
          ),
        ],
      ),
    );
  }
}
