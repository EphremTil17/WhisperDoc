import 'package:flutter/material.dart';
import 'package:flutter_client/core/models/transcription_entry.dart';
import 'package:flutter_client/core/controllers/recording_controller.dart';
import 'package:flutter_client/ui/shared/widgets/glass_dialog.dart';
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

    return GlassDialog(
      title: 'Transcription History',
      titleTrailing: controller.incognitoMode
          ? const DialogBadge(text: 'INCOGNITO')
          : null,
      body: history.isEmpty
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
          Consumer<RecordingController>(
            builder: (context, controller, child) => SelectableText(
              controller.getDecryptedText(entry),
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.4,
                fontFamily: GoogleFonts.lexend().fontFamily,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
