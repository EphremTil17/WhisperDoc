import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_client/services/utility/clipboard_service.dart';
import 'package:flutter_client/infrastructure/theme/app_theme.dart';
import 'package:google_fonts/google_fonts.dart';

class TranscribedTextArea extends StatefulWidget {
  const TranscribedTextArea({super.key, required this.text});

  final String text;

  @override
  State<TranscribedTextArea> createState() => _TranscribedTextAreaState();
}

class _TranscribedTextAreaState extends State<TranscribedTextArea> {
  static const _copiedAlpha = 0.15;
  static const _idleAlpha = 0.05;
  static const _borderAlpha = 0.1;
  static const _minHeight = 100.0;
  static const _borderRadius = 24.0;
  static const _contentPadding = EdgeInsets.fromLTRB(20, 20, 20, 36);
  static const _fontSize = 16.0;
  static const _lineHeight = 1.5;
  static const _buttonRight = 12.0;
  static const _buttonBottom = 8.0;
  static const _buttonHorizontalPadding = 8.0;
  static const _buttonVerticalPadding = 4.0;
  static const _buttonBorderRadius = 6.0;
  static const _iconSize = 14.0;
  static const _labelGap = SizedBox(width: 4);
  static const _copyAnimationDuration = Duration(milliseconds: 200);
  static const _labelFontSize = 11.0;

  bool _copied = false;

  Future<void> _copyToClipboard() async {
    final text = widget.text;
    if (text.isEmpty) return;

    await ClipboardService.copyToClipboard(text);

    if (!mounted) return;

    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    setState(() => _copied = false);
  }

  void _handleCopyTap() {
    unawaited(_copyToClipboard());
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    final hasText = text.isNotEmpty;
    final fontFamily = GoogleFonts.lexend().fontFamily;
    final buttonColor = _copied
        ? Colors.greenAccent.withValues(alpha: _copiedAlpha)
        : Colors.white.withValues(alpha: _idleAlpha);
    final iconColor = _copied ? Colors.greenAccent : Colors.white30;

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: _minHeight),
      decoration: AppTheme.glassDecoration.copyWith(
        borderRadius: const BorderRadius.all(Radius.circular(_borderRadius)),
        border: Border.all(color: Colors.white.withValues(alpha: _borderAlpha)),
      ),
      child: Stack(
        children: [
          // Text content with padding
          Padding(
            padding: _contentPadding,
            child: SingleChildScrollView(
              reverse: true,
              child: SelectableText(
                text.isEmpty ? 'Transcription will appear here...' : text,
                style: TextStyle(
                  fontSize: _fontSize,
                  height: _lineHeight,
                  color: text.isEmpty ? Colors.white38 : Colors.white,
                  fontFamily: fontFamily,
                ),
              ),
            ),
          ),
          // Copy button - positioned inside, at bottom right
          if (hasText)
            Positioned(
              right: _buttonRight,
              bottom: _buttonBottom,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: _handleCopyTap,
                  child: AnimatedContainer(
                    duration: _copyAnimationDuration,
                    padding: const EdgeInsets.symmetric(
                      horizontal: _buttonHorizontalPadding,
                      vertical: _buttonVerticalPadding,
                    ),
                    decoration: BoxDecoration(
                      color: buttonColor,
                      borderRadius: const BorderRadius.all(
                        Radius.circular(_buttonBorderRadius),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _copied ? Icons.check : Icons.copy_outlined,
                          color: iconColor,
                          size: _iconSize,
                        ),
                        if (_copied) ...[
                          _labelGap,
                          Text(
                            'Copied',
                            style: TextStyle(
                              color: Colors.greenAccent,
                              fontSize: _labelFontSize,
                              fontFamily: fontFamily,
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
