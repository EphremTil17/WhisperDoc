import 'dart:async';

import 'package:flutter_client/controllers/recording_controller.dart';
import 'package:flutter_client/infrastructure/theme/app_icons.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/logic/formatters/clock_time.dart';
import 'package:flutter_client/logic/models/history_entry.dart';
import 'package:flutter_client/services/utility/clipboard_service.dart';
import 'package:flutter_client/services/utility/logging_service.dart';
import 'package:flutter_client/ui/shared/widgets/caption_cue.dart';
import 'package:flutter_client/ui/shared/widgets/crisp_text.dart';
import 'package:flutter_client/ui/shared/widgets/panel/app_panel.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Past transcripts, newest first: when, the text, and a copy action,
/// separated by rules. Incognito keeps it empty and says so.
class HistoryPanel extends StatefulWidget {
  const HistoryPanel({super.key});

  @override
  State<HistoryPanel> createState() => _HistoryPanelState();
}

class _HistoryPanelState extends State<HistoryPanel> {
  /// Plaintext per entry, decrypted at most once while the panel is open.
  /// Weakly keyed, so it is released with the entries (and the panel);
  /// decrypted history is never held by the long-lived controller.
  final Expando<String> _plaintext = Expando('historyPlaintext');

  /// Empty when the entry cannot be decrypted (a reset vault key, a damaged
  /// row): cached too, so a bad entry is tried once, not on every rebuild.
  String _textOf(RecordingController controller, HistoryEntry entry) {
    final cached = _plaintext[entry];
    if (cached != null) return cached;
    var text = '';
    try {
      text = controller.getDecryptedText(entry);
    } catch (e) {
      LoggingService().warning('History entry could not be decrypted: $e');
    }

    return _plaintext[entry] = text;
  }

  Future<void> _copy(String text) async {
    final copied = await ClipboardService.copyToClipboard(text);
    if (!copied || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: CrispText('Copied', style: AppType.caption)),
    );
  }

  @override
  Widget build(BuildContext context) {
    // history is a fresh list on every read, so select its revision instead.
    final (_, incognito) = context.select(
      (RecordingController c) => (c.historyRevision, c.incognitoMode),
    );
    final controller = context.read<RecordingController>();
    final history = controller.history;
    final now = DateTime.now();

    return AppPanel(
      title: 'History',
      body: history.isEmpty
          ? Center(
              child: CaptionCue(
                incognito
                    ? 'incognito · nothing is saved'
                    : 'no transcripts yet',
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
              itemCount: history.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final entry = history[index];
                final text = _textOf(controller, entry);

                return Padding(
                  padding: const EdgeInsets.only(
                    top: AppSpace.xs,
                    bottom: AppSpace.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: CrispText(
                              ClockTime.stamp(entry.timestamp, now),
                              style: AppType.caption.copyWith(
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                          if (text.isNotEmpty)
                            IconButton(
                              tooltip: 'Copy',
                              onPressed: () => unawaited(_copy(text)),
                              icon: const Icon(
                                AppIcons.copy,
                                size: AppSizes.smallIconSize,
                              ),
                            ),
                        ],
                      ),
                      if (text.isEmpty)
                        const CaptionCue("can't read this entry")
                      else
                        CrispText(text, style: AppType.body),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
