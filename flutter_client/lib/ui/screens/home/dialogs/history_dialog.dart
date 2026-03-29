import 'package:flutter/material.dart';
import 'package:flutter_client/controllers/recording_controller.dart';
import 'package:flutter_client/ui/shared/widgets/glass_dialog.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

class HistoryDialog extends StatelessWidget {
  const HistoryDialog({super.key});

  static const _timestampComponentPadWidth = 2;
  static const _emptyStateIconSize = 48.0;
  static const _emptyStateMessageFontSize = 12.0;
  static const _historyEntryBackgroundAlpha = 0.05;
  static const _historyEntryBorderAlpha = 0.08;
  static const _historyEntryTimestampFontSize = 10.0;
  static const _historyEntryTextFontSize = 13.0;
  static const _historyEntryTextLineHeight = 1.4;
  static const _badgeHorizontalPadding = 6.0;
  static const _badgeVerticalPadding = 2.0;
  static const _badgeRadius = 4.0;
  static const _badgeBackgroundAlpha = 0.2;
  static const _badgeFontSize = 9.0;

  String _formatTimestamp(DateTime dt) {
    return '${dt.hour.toString().padLeft(_timestampComponentPadWidth, '0')}:'
        '${dt.minute.toString().padLeft(_timestampComponentPadWidth, '0')}:'
        '${dt.second.toString().padLeft(_timestampComponentPadWidth, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<RecordingController>();
    final history = controller.history;
    const badgeColor = Colors.orangeAccent;

    return GlassDialog(
      title: 'Transcription History',
      titleTrailing: controller.incognitoMode
          ? Container(
              padding: const EdgeInsets.symmetric(
                horizontal: _badgeHorizontalPadding,
                vertical: _badgeVerticalPadding,
              ),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: _badgeBackgroundAlpha),
                borderRadius: const BorderRadius.all(
                  Radius.circular(_badgeRadius),
                ),
              ),
              child: const Text(
                'INCOGNITO',
                style: TextStyle(
                  color: badgeColor,
                  fontSize: _badgeFontSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
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
                    size: _emptyStateIconSize,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    controller.incognitoMode
                        ? 'Incognito mode active\nHistory is disabled'
                        : 'No transcriptions yet',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: _emptyStateMessageFontSize,
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
                final timestamp = _formatTimestamp(entry.timestamp);

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(
                      alpha: _historyEntryBackgroundAlpha,
                    ),
                    borderRadius: const BorderRadius.all(Radius.circular(8)),
                    border: Border.all(
                      color: Colors.white.withValues(
                        alpha: _historyEntryBorderAlpha,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        timestamp,
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: _historyEntryTimestampFontSize,
                          fontFamily: GoogleFonts.jetBrainsMono().fontFamily,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Consumer<RecordingController>(
                        builder: (context, controller, child) => SelectableText(
                          controller.getDecryptedText(entry),
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: _historyEntryTextFontSize,
                            height: _historyEntryTextLineHeight,
                            fontFamily: GoogleFonts.lexend().fontFamily,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
