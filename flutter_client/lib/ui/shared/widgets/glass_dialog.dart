import 'package:flutter/material.dart';
import 'package:flutter_client/infrastructure/theme/app_theme.dart';
import 'package:google_fonts/google_fonts.dart';

/// A reusable glassmorphic dialog container.
///
/// Encapsulates the common pattern of:
/// - Transparent background
/// - Glass decoration with border
/// - Header with title and close button
/// - Scrollable body area
/// - Optional footer
///
/// Usage:
/// ```dart
/// showDialog(
///   context: context,
///   builder: (_) => GlassDialog(
///     title: 'My Dialog',
///     body: MyContent(),
///     footer: MyFooter(), // optional
///   ),
/// );
/// ```
class GlassDialog extends StatelessWidget {
  /// The title displayed in the dialog header.
  final String title;

  /// Optional widget displayed after the title (e.g., a badge).
  final Widget? titleTrailing;

  /// The main content of the dialog.
  final Widget body;

  /// Optional footer widget (e.g., version + Done button).
  final Widget? footer;

  /// Maximum width constraint for the dialog.
  final double maxWidth;

  /// If true, dialog sizes to content. If false, expands to fill available space.
  final bool shrinkWrap;

  const GlassDialog({
    super.key,
    required this.title,
    required this.body,
    this.titleTrailing,
    this.footer,
    this.maxWidth = 500,
    this.shrinkWrap = false,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        decoration: AppTheme.glassDecoration.copyWith(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Column(
          mainAxisSize: shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          fontFamily: GoogleFonts.lexend().fontFamily,
                        ),
                      ),
                      if (titleTrailing != null) ...[
                        const SizedBox(width: 8),
                        titleTrailing!,
                      ],
                    ],
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white54,
                      size: 18,
                    ),
                    splashRadius: 16,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            // Body
            shrinkWrap ? Flexible(child: body) : Expanded(child: body),
            // Footer (optional)
            if (footer != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                ),
                child: footer,
              ),
          ],
        ),
      ),
    );
  }
}

/// A badge widget for use with GlassDialog's titleTrailing.
///
/// Example: Incognito mode indicator.
class DialogBadge extends StatelessWidget {
  final String text;
  final Color color;

  const DialogBadge({
    super.key,
    required this.text,
    this.color = Colors.orangeAccent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
