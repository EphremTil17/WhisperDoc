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

  List<TextSpan> _buildLogSpans({
    required List<LogEntry> logs,
    required String? monoFontFamily,
  }) {
    final spans = <TextSpan>[];

    for (var i = 0; i < logs.length; i++) {
      final entry = logs[i];

      spans.addAll([
        TextSpan(
          text: _LogViewerDialogStyling.formatTimestamp(entry.timestamp),
          style: _LogViewerDialogStyling.monoTextStyle(
            color: Colors.grey,
            fontFamily: monoFontFamily,
            fontSize: _LogViewerDialogStyling.logFontSize,
            height: _LogViewerDialogStyling.logLineHeight,
          ),
        ),
        TextSpan(
          text: ' | ',
          style: _LogViewerDialogStyling.monoTextStyle(
            color: Colors.white38,
            fontFamily: monoFontFamily,
            fontSize: _LogViewerDialogStyling.logFontSize,
            height: _LogViewerDialogStyling.logLineHeight,
          ),
        ),
        TextSpan(
          text: entry.level.padRight(_LogViewerDialogStyling.levelWidth),
          style: _LogViewerDialogStyling.monoTextStyle(
            color: _LogViewerDialogStyling.levelColor(entry.level),
            fontFamily: monoFontFamily,
            fontSize: _LogViewerDialogStyling.logFontSize,
            height: _LogViewerDialogStyling.logLineHeight,
          ),
        ),
        TextSpan(
          text: ' | ',
          style: _LogViewerDialogStyling.monoTextStyle(
            color: Colors.white38,
            fontFamily: monoFontFamily,
            fontSize: _LogViewerDialogStyling.logFontSize,
            height: _LogViewerDialogStyling.logLineHeight,
          ),
        ),
        TextSpan(
          text: '${entry.message}${i < logs.length - 1 ? '\n' : ''}',
          style: _LogViewerDialogStyling.monoTextStyle(
            color: Colors.white70,
            fontFamily: monoFontFamily,
            fontSize: _LogViewerDialogStyling.logFontSize,
            height: _LogViewerDialogStyling.logLineHeight,
          ),
        ),
      ]);
    }

    return spans;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final monoFontFamily = GoogleFonts.jetBrainsMono().fontFamily;
    final loggingService = LoggingService();

    return GlassDialog(
      title: 'Application Logs',
      body: StreamBuilder<LogEntry>(
        stream: loggingService.onLog,
        builder: (context, _) {
          final logs = loggingService.logs;

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
                style: _LogViewerDialogStyling.monoTextStyle(
                  color: Colors.white38,
                  fontFamily: monoFontFamily,
                  fontSize: _LogViewerDialogStyling.emptyStateFontSize,
                ),
              ),
            );
          }

          return SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.all(
              _LogViewerDialogStyling.logContentPadding,
            ),
            child: SelectableText.rich(
              TextSpan(
                children: _buildLogSpans(
                  logs: logs,
                  monoFontFamily: monoFontFamily,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

final class _LogViewerDialogStyling {
  static const emptyStateFontSize = 12.0;
  static const logFontSize = 11.0;
  static const logLineHeight = 1.5;
  static const logContentPadding = 12.0;
  static const timeComponentWidth = 2;
  static const levelWidth = 5;

  const _LogViewerDialogStyling._();

  static String formatTimestamp(DateTime timestamp) {
    final hour = timestamp.hour.toString().padLeft(timeComponentWidth, '0');
    final minute = timestamp.minute.toString().padLeft(timeComponentWidth, '0');
    final second = timestamp.second.toString().padLeft(timeComponentWidth, '0');

    return '$hour:$minute:$second';
  }

  static TextStyle monoTextStyle({
    required Color color,
    required String? fontFamily,
    required double fontSize,
    double? height,
  }) {
    return TextStyle(
      color: color,
      fontSize: fontSize,
      fontFamily: fontFamily,
      height: height,
    );
  }

  static Color levelColor(String level) {
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
}
