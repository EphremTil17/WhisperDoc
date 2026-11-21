import 'dart:async';

import 'package:flutter_client/infrastructure/theme/app_icons.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/services/utility/clipboard_service.dart';
import 'package:flutter_client/services/utility/logging_service.dart';
import 'package:flutter_client/ui/shared/widgets/caption_cue.dart';
import 'package:flutter_client/ui/shared/widgets/crisp_text.dart';
import 'package:flutter_client/ui/shared/widgets/panel/app_panel.dart';
import 'package:material_ui/material_ui.dart';

/// The app's log in mono, newest at the bottom: a fixed `time  LEVEL`
/// column, then the message wrapping beside it. Errors read in alert,
/// warnings in white, the rest muted. Follows new lines while scrolled to
/// the end; only visible lines are built.
class LogsPanel extends StatefulWidget {
  const LogsPanel({super.key});

  @override
  State<LogsPanel> createState() => _LogsPanelState();
}

class _LogsPanelState extends State<LogsPanel> {
  /// How close to the end still counts as "following".
  static const double _pinSlack = 24;

  /// `HH:mm:ss  LEVEL` (15 mono characters, about 111px) plus a gap.
  static const double _prefixWidth = 128;

  static final TextStyle _base = AppType.mono.copyWith(
    color: AppColors.textMuted,
  );
  static final TextStyle _error = _base.copyWith(color: AppColors.alert);
  static final TextStyle _warn = _base.copyWith(color: AppColors.text);

  final ScrollController _scroll = ScrollController();
  final LoggingService _logging = LoggingService();
  StreamSubscription<LogEntry>? _subscription;
  List<LogEntry> _logs = const [];

  static TextStyle _levelStyle(String level) => switch (level) {
    'ERROR' => _error,
    'WARN' => _warn,
    _ => _base,
  };

  @override
  void initState() {
    super.initState();
    _logs = _logging.logs;
    _subscription = _logging.onLog.listen((_) => _append());
    _jumpToEnd();
  }

  bool get _pinned {
    if (!_scroll.hasClients) return true;
    final position = _scroll.position;

    return position.pixels >= position.maxScrollExtent - _pinSlack;
  }

  /// Takes the new line; stays at the end only if already there, so
  /// scrolling up to read is not yanked back on every entry.
  void _append() {
    final follow = _pinned;
    setState(() => _logs = _logging.logs);
    if (follow) _jumpToEnd();
  }

  void _jumpToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _copyAll() async {
    final text = _logs.map((e) => e.formatted).join('\n');
    final copied = await ClipboardService.copyToClipboard(text);
    if (!copied || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: CrispText('Logs copied', style: AppType.caption),
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      title: 'Logs',
      actions: [
        IconButton(
          tooltip: 'Copy all',
          onPressed: _logs.isEmpty ? null : () => unawaited(_copyAll()),
          icon: const Icon(AppIcons.copy),
        ),
      ],
      body: _logs.isEmpty
          ? const Center(child: CaptionCue('no logs yet'))
          : SelectionArea(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.lg,
                  vertical: AppSpace.sm,
                ),
                itemCount: _logs.length,
                itemBuilder: (context, index) {
                  final entry = _logs[index];
                  final style = _levelStyle(entry.level);

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: _prefixWidth,
                        child: CrispText(
                          '${entry.time}  ${entry.paddedLevel}',
                          style: style,
                        ),
                      ),
                      Expanded(child: CrispText(entry.message, style: style)),
                    ],
                  );
                },
              ),
            ),
    );
  }
}
