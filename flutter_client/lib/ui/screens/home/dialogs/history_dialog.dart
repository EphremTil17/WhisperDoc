import 'package:material_ui/material_ui.dart';
import 'package:flutter_client/controllers/recording_controller.dart';
import 'package:flutter_client/logic/formatters/clock_time.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/logic/models/history_entry.dart';
import 'package:flutter_client/ui/shared/widgets/glass_dialog.dart';
import 'package:provider/provider.dart';

class HistoryDialog extends StatefulWidget {
  const HistoryDialog({super.key});

  @override
  State<HistoryDialog> createState() => _HistoryDialogState();
}

class _HistoryDialogState extends State<HistoryDialog> {
  static const _emptyStateIconSize = 48.0;
  static const _emptyStateMessageFontSize = 12.0;
  static const _historyEntryBackgroundAlpha = 0.05;
  static const _historyEntryBorderAlpha = 0.08;
  static const _historyEntryTextFontSize = 13.0;
  static const _historyEntryTextLineHeight = 1.4;
  static const _badgeHorizontalPadding = 6.0;
  static const _badgeVerticalPadding = 2.0;
  static const _badgeRadius = 4.0;
  static const _badgeBackgroundAlpha = 0.2;
  static const _badgeFontSize = 9.0;

  static const TextStyle _timestampStyle = TextStyle(
    color: Colors.white38,
    fontSize: 10,
    fontFamily: AppType.monoFamily,
  );

  /// Plaintext per entry, decrypted at most once while the dialog is open.
  /// Weakly keyed, so it is released with the entries (and the dialog);
  /// decrypted history is never held by the long-lived controller.
  final Expando<String> _plaintext = Expando('historyPlaintext');

  String _textOf(RecordingController controller, HistoryEntry entry) =>
      _plaintext[entry] ??= controller.getDecryptedText(entry);

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
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: _emptyStateMessageFontSize,
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
                        ClockTime.hms(entry.timestamp),
                        style: _timestampStyle,
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        _textOf(controller, entry),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: _historyEntryTextFontSize,
                          height: _historyEntryTextLineHeight,
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
