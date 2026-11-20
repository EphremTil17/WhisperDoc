import 'package:flutter/material.dart';
import 'package:flutter_client/services/utility/logging_service.dart';
import 'package:flutter_client/ui/shared/widgets/glass_dialog.dart';
import 'package:google_fonts/google_fonts.dart';

class LogViewerDialog extends StatefulWidget {
  const LogViewerDialog({super.key});

  @override
  State<LogViewerDialog> createState() => _LogViewerDialogState();
}

class _LogViewerDialogState extends State<LogViewerDialog> {
  final ScrollController _scrollController = ScrollController();

  /// One TextSpan per entry (a single selectable block so multi-line copy
  /// works); styles are shared, so a new log line costs little.
  List<TextSpan> _buildLogSpans(List<LogEntry> logs) {
    final last = logs.length - 1;

    return [
      for (final (i, entry) in logs.indexed)
        TextSpan(
          children: [
            TextSpan(text: entry.time, style: _LogStyles.timestamp),
            TextSpan(text: ' | ', style: _LogStyles.separator),
            TextSpan(
              text: entry.paddedLevel,
              style: _LogStyles.level(entry.level),
            ),
            TextSpan(text: ' | ', style: _LogStyles.separator),
            TextSpan(
              text: i < last ? '${entry.message}\n' : entry.message,
              style: _LogStyles.message,
            ),
          ],
        ),
    ];
  }

  /// Follow new logs only while the user is already at the bottom, so
  /// scrolling up to read is not yanked back on every new line.
  void _followTailIfPinned() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final pinned =
        position.pixels >= position.maxScrollExtent - _LogStyles.pinSlack;
    if (!pinned) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loggingService = LoggingService();

    return GlassDialog(
      title: 'Application Logs',
      body: StreamBuilder<LogEntry>(
        stream: loggingService.onLog,
        builder: (context, _) {
          final logs = loggingService.logs;
          if (logs.isEmpty) {
            return const Center(
              child: Text('No logs yet', style: _LogStyles.emptyState),
            );
          }
          _followTailIfPinned();

          return SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.all(_LogStyles.contentPadding),
            child: SelectableText.rich(
              TextSpan(children: _buildLogSpans(logs)),
            ),
          );
        },
      ),
    );
  }
}

/// Shared, allocation-free styles for the log view.
abstract final class _LogStyles {
  static const contentPadding = 12.0;
  static const pinSlack = 24.0;
  static const _fontSize = 11.0;
  static const _lineHeight = 1.5;

  static final String? _mono = GoogleFonts.jetBrainsMono().fontFamily;

  static final TextStyle _base = TextStyle(
    fontFamily: _mono,
    fontSize: _fontSize,
    height: _lineHeight,
  );
  static final TextStyle timestamp = _base.copyWith(color: Colors.grey);
  static final TextStyle separator = _base.copyWith(color: Colors.white38);
  static final TextStyle message = _base.copyWith(color: Colors.white70);
  static const TextStyle emptyState = TextStyle(
    color: Colors.white38,
    fontSize: 12,
  );

  static final TextStyle _error = _base.copyWith(color: Colors.redAccent);
  static final TextStyle _warn = _base.copyWith(color: Colors.orangeAccent);
  static final TextStyle _debug = _base.copyWith(color: Colors.grey);
  static final TextStyle _info = _base.copyWith(color: Colors.cyanAccent);

  static TextStyle level(String level) => switch (level) {
    'ERROR' => _error,
    'WARN' => _warn,
    'DEBUG' => _debug,
    'INFO' => _info,
    _ => message,
  };
}
