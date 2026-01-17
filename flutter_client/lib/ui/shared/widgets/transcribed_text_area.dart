import 'package:flutter/material.dart';
import 'package:flutter_client/core/services/clipboard_service.dart';
import 'package:flutter_client/ui/theme/app_theme.dart';
import 'package:google_fonts/google_fonts.dart';

class TranscribedTextArea extends StatefulWidget {
  final String text;

  const TranscribedTextArea({super.key, required this.text});

  @override
  State<TranscribedTextArea> createState() => _TranscribedTextAreaState();
}

class _TranscribedTextAreaState extends State<TranscribedTextArea> {
  bool _copied = false;

  Future<void> _copyToClipboard() async {
    if (widget.text.isEmpty) return;
    await ClipboardService.copyToClipboard(widget.text);
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 100),
      decoration: AppTheme.glassDecoration.copyWith(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Stack(
        children: [
          // Text content with padding
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
            child: SingleChildScrollView(
              reverse: true,
              child: SelectableText(
                widget.text.isEmpty
                    ? 'Transcription will appear here...'
                    : widget.text,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.5,
                  color: widget.text.isEmpty ? Colors.white38 : Colors.white,
                  fontFamily: GoogleFonts.lexend().fontFamily,
                ),
              ),
            ),
          ),
          // Copy button - positioned inside, at bottom right
          if (widget.text.isNotEmpty)
            Positioned(
              right: 12,
              bottom: 8,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: _copyToClipboard,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _copied
                          ? Colors.greenAccent.withValues(alpha: 0.15)
                          : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _copied ? Icons.check : Icons.copy_outlined,
                          color: _copied ? Colors.greenAccent : Colors.white30,
                          size: 14,
                        ),
                        if (_copied) ...[
                          const SizedBox(width: 4),
                          Text(
                            'Copied',
                            style: TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 11,
                              fontFamily: GoogleFonts.lexend().fontFamily,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
