import 'package:flutter/material.dart';
import 'package:flutter_client/core/services/logging_service.dart';
import 'package:flutter_client/ui/shared/widgets/glass_dialog.dart';
import 'package:google_fonts/google_fonts.dart';

class LogViewerDialog extends StatefulWidget {
  const LogViewerDialog({super.key});

  @override
  State<LogViewerDialog> createState() => _LogViewerDialogState();
}

class _LogViewerDialogState extends State<LogViewerDialog> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Color _levelColor(String level) {
    switch (level.trim()) {
      case 'ERROR':
        return Colors.redAccent;
      case 'WARN':
        return Colors.orangeAccent;
      case 'DEBUG':
        return Colors.grey;
      case 'INFO':
        return Colors.cyanAccent;
      default:
        return Colors.white70;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassDialog(title: 'Application Logs', body: _buildLogContent());
  }

  Widget _buildLogContent() {
    final monoFont = GoogleFonts.jetBrainsMono().fontFamily;

    return StreamBuilder<LogEntry>(
      stream: LoggingService().onLog,
      builder: (context, snapshot) {
        final logs = LoggingService().logs;

        // Auto-scroll to bottom when new entry arrives
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(
              _scrollController.position.maxScrollExtent,
            );
          }
        });

        if (logs.isEmpty) {
          return Center(
            child: Text(
              'No logs yet',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 12,
                fontFamily: monoFont,
              ),
            ),
          );
        }

        // Build colored TextSpans matching terminal style:
        // gray timestamp | colored level | white message
        final spans = <TextSpan>[];
        for (int i = 0; i < logs.length; i++) {
          final entry = logs[i];
          final timeStr =
              '${entry.timestamp.hour.toString().padLeft(2, '0')}:'
              '${entry.timestamp.minute.toString().padLeft(2, '0')}:'
              '${entry.timestamp.second.toString().padLeft(2, '0')}';

          spans.addAll([
            // Gray timestamp
            TextSpan(
              text: timeStr,
              style: TextStyle(
                color: Colors.grey,
                fontSize: 11,
                fontFamily: monoFont,
                height: 1.5,
              ),
            ),
            // Separator
            TextSpan(
              text: ' | ',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 11,
                fontFamily: monoFont,
                height: 1.5,
              ),
            ),
            // Colored level
            TextSpan(
              text: entry.level.padRight(5),
              style: TextStyle(
                color: _levelColor(entry.level),
                fontSize: 11,
                fontFamily: monoFont,
                height: 1.5,
              ),
            ),
            // Separator
            TextSpan(
              text: ' | ',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 11,
                fontFamily: monoFont,
                height: 1.5,
              ),
            ),
            // White message
            TextSpan(
              text: '${entry.message}${i < logs.length - 1 ? '\n' : ''}',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontFamily: monoFont,
                height: 1.5,
              ),
            ),
          ]);
        }

        return SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.all(12),
          child: SelectableText.rich(TextSpan(children: spans)),
        );
      },
    );
  }
}
