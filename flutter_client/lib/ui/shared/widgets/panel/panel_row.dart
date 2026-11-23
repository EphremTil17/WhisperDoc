import 'package:flutter_client/infrastructure/theme/app_icons.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/ui/shared/widgets/crisp_text.dart';
import 'package:flutter_client/ui/shared/widgets/press_nudge.dart';
import 'package:material_ui/material_ui.dart';

/// One line in a panel: icon, label (and an optional subtitle), the current
/// value, then a chevron when it opens something, or a [trailing] control.
///
/// Rows are 48px with a 1px rule beneath (except a panel's last row, where
/// nothing follows it); hover and press fill with band.
/// A disabled row keeps its value readable but mutes its label and icon.
class PanelRow extends StatelessWidget {
  const PanelRow({
    super.key,
    required this.label,
    this.icon,
    this.iconColor,
    this.subtitle,
    this.subtitleColor,
    this.value,
    this.valueColor,
    this.trailing,
    this.chevron,
    this.onTap,
    this.enabled = true,
    this.rule = true,
  });

  static const double _iconGap = 24;
  static const double _valueMaxWidth = 168;

  final String label;
  final IconData? icon;

  /// Overrides the muted icon colour (alert, update).
  final Color? iconColor;

  final String? subtitle;
  final Color? subtitleColor;

  /// The current setting, set small and muted before the chevron.
  final String? value;
  final Color? valueColor;

  /// A control at the end of the row (switch, button, keycap).
  final Widget? trailing;

  /// Shows the chevron. Defaults to true for tappable rows without [trailing].
  final bool? chevron;

  /// [subtitle] for a row whose change would cut off the dictation under way.
  static const String lockedWhileRecording = 'Stop recording to change';

  final VoidCallback? onTap;
  final bool enabled;

  /// Draws the 1px rule beneath. Off for the last row of a panel.
  final bool rule;

  static const BoxDecoration _ruled = BoxDecoration(
    border: Border(bottom: BorderSide(color: AppColors.rule)),
  );

  @override
  Widget build(BuildContext context) {
    final glyph = icon;
    final note = subtitle;
    final current = value;
    final control = trailing;
    final tap = enabled ? onTap : null;
    final showChevron = chevron ?? (control == null && tap != null);

    return InkWell(
      onTap: tap,
      borderRadius: AppRadius.controlAll,
      hoverColor: AppColors.band,
      highlightColor: AppColors.band,
      focusColor: AppColors.band,
      splashFactory: NoSplash.splashFactory,
      // The rule spans the row's full width, like the hover band, so a band
      // meets the rule above it edge to edge; the press moves the content,
      // never the rule.
      child: DecoratedBox(
        decoration: rule ? _ruled : const BoxDecoration(),
        child: PressNudge(
          enabled: tap != null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppSizes.row),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
                child: Row(
                  children: [
                    if (glyph != null) ...[
                      Icon(
                        glyph,
                        size: AppSizes.smallIconSize,
                        color: enabled
                            ? iconColor ?? AppColors.textMuted
                            : AppColors.iconFaint,
                      ),
                      const SizedBox(width: _iconGap),
                    ],
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CrispText(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.body.copyWith(
                              color: enabled
                                  ? AppColors.text
                                  : AppColors.textMuted,
                            ),
                          ),
                          if (note != null)
                            CrispText(
                              note,
                              style: AppType.caption.copyWith(
                                color: subtitleColor ?? AppColors.textMuted,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (current != null)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          start: AppSpace.sm,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: _valueMaxWidth,
                          ),
                          child: CrispText(
                            current,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.caption.copyWith(
                              color: valueColor ?? AppColors.textMuted,
                            ),
                          ),
                        ),
                      ),
                    if (control != null)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          start: AppSpace.sm,
                        ),
                        child: control,
                      ),
                    if (showChevron)
                      const Padding(
                        padding: EdgeInsetsDirectional.only(start: AppSpace.xs),
                        child: Icon(
                          AppIcons.chevronRight,
                          size: AppSizes.smallIconSize,
                          color: AppColors.iconFaint,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
