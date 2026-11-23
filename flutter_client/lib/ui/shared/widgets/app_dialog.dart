import 'package:flutter_client/infrastructure/theme/app_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/ui/shared/widgets/crisp_text.dart';

/// The one dialog shell: a flat raised surface with a 1px rule, a title row
/// with a close button, a body, and an optional footer. Only for short
/// interruptions (confirmations, the shortcut recorder, the style editor);
/// places the user goes to are panels (see AppPanel).
///
/// ```dart
/// showDialog(
///   context: context,
///   builder: (_) => AppDialog(title: 'Shortcut', body: Recorder()),
/// );
/// ```
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    required this.body,
    this.titleTrailing,
    this.footer,
    this.maxWidth = _defaultMaxWidth,
    this.shrinkWrap = false,
  });

  static const double _defaultMaxWidth = 500;

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

  /// If true, the dialog sizes to its content; otherwise it fills the
  /// available height.
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    const rule = BorderSide(color: AppColors.rule);
    final bottom = footer;

    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.all(AppSpace.lg),
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadius.controlAll,
        side: rule,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Column(
          mainAxisSize: shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
          children: [
            DecoratedBox(
              decoration: const BoxDecoration(border: Border(bottom: rule)),
              child: SizedBox(
                height: AppSizes.header,
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: AppSpace.lg,
                    end: AppSpace.xs,
                  ),
                  child: Row(
                    children: [
                      // The title area takes all free space, so the close
                      // button always sits at the right edge.
                      Expanded(
                        child: Row(
                          spacing: AppSpace.sm,
                          children: [
                            Flexible(
                              child: CrispText(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppType.body.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            ?titleTrailing,
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(AppIcons.x),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (shrinkWrap) Flexible(child: body) else Expanded(child: body),
            if (bottom != null)
              DecoratedBox(
                decoration: const BoxDecoration(border: Border(top: rule)),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpace.lg),
                  child: bottom,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
