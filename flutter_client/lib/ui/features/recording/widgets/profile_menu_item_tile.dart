import 'package:material_ui/material_ui.dart';
import 'package:flutter_client/infrastructure/theme/app_icons.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/logic/mappers/dictation_profile_ui_mapper.dart';
import 'package:flutter_client/logic/models/dictation_profile_spec.dart';
import 'package:flutter_client/ui/shared/widgets/crisp_text.dart';

/// One output style in the [ProfileActionButton] menu: glyph, name and a
/// one-line description; the active style is filled and checked.
class ProfileMenuItemTile extends StatefulWidget {
  const ProfileMenuItemTile({
    required this.profile,
    required this.isSelected,
    required this.isEnabled,
    required this.isKeyBlocked,
    required this.onTap,
    this.onEdit,
    super.key,
  });

  final DictationProfileSpec profile;
  final bool isSelected;
  final bool isEnabled;
  final bool isKeyBlocked;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;

  static const EdgeInsets _padding = EdgeInsets.symmetric(
    horizontal: AppSpace.md,
    vertical: AppSpace.sm,
  );

  /// The edit button's target, larger than its 16px glyph.
  static const double _editTarget = 28;

  @override
  State<ProfileMenuItemTile> createState() => _ProfileMenuItemTileState();
}

class _ProfileMenuItemTileState extends State<ProfileMenuItemTile> {
  bool _isHovered = false;
  bool _isFocused = false;

  void _activate() => widget.onTap?.call();

  @override
  Widget build(BuildContext context) {
    final enabled = widget.isEnabled;
    final filled = widget.isSelected || (_isHovered && enabled);
    // Faint is for icons only; unavailable text steps down to muted.
    final ink = enabled ? AppColors.text : AppColors.textMuted;
    const meta = AppColors.textMuted;
    final label = widget.profile.label;
    final description = DictationProfileUiMapper.subtitleFor(
      widget.profile,
      isKeyBlocked: widget.isKeyBlocked,
    );
    final onEdit = widget.onEdit;

    // A button to the keyboard and screen readers too: focusable unless
    // unavailable, Enter or Space picks it, and its name, description and
    // selection are announced. The menu opens focused on the current style.
    return Semantics(
      button: true,
      enabled: enabled,
      selected: widget.isSelected,
      label: '$label, $description',
      child: FocusableActionDetector(
        enabled: enabled,
        autofocus: widget.isSelected,
        mouseCursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onShowHoverHighlight: (on) => setState(() => _isHovered = on),
        onShowFocusHighlight: (on) => setState(() => _isFocused = on),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) => _activate(),
          ),
        },
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: AppMotion.quick,
            padding: ProfileMenuItemTile._padding,
            decoration: BoxDecoration(
              color: filled ? AppColors.band : Colors.transparent,
              borderRadius: AppRadius.controlAll,
              // The keyboard ring stays distinct from the selected fill.
              border: Border.all(
                color: _isFocused ? AppColors.textMuted : Colors.transparent,
              ),
            ),
            child: Row(
              spacing: AppSpace.md,
              children: [
                Icon(
                  DictationProfileUiMapper.iconFor(widget.profile),
                  size: AppSizes.smallIconSize,
                  color: enabled ? AppColors.textMuted : AppColors.iconFaint,
                ),
                Expanded(
                  // The row's own label already says this to screen readers.
                  child: ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CrispText(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.caption.copyWith(
                            color: ink,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        CrispText(
                          description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.caption.copyWith(color: meta),
                        ),
                      ],
                    ),
                  ),
                ),
                if (onEdit != null)
                  IconButton(
                    onPressed: onEdit,
                    tooltip: 'Edit $label',
                    icon: const Icon(AppIcons.pencil),
                    iconSize: AppSizes.smallIconSize,
                    color: AppColors.textMuted,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: ProfileMenuItemTile._editTarget,
                      height: ProfileMenuItemTile._editTarget,
                    ),
                  ),
                if (widget.isSelected)
                  const Icon(
                    AppIcons.check,
                    size: AppSizes.smallIconSize,
                    color: AppColors.text,
                  )
                else if (widget.isKeyBlocked)
                  const Icon(
                    AppIcons.keyRound,
                    size: AppSizes.smallIconSize,
                    color: AppColors.iconFaint,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
