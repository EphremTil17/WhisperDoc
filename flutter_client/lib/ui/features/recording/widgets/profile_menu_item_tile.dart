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
  static const double _editPadStart = AppSpace.sm;

  @override
  State<ProfileMenuItemTile> createState() => _ProfileMenuItemTileState();
}

class _ProfileMenuItemTileState extends State<ProfileMenuItemTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.isEnabled;
    final filled = widget.isSelected || (_isHovered && enabled);
    // Faint is for icons only; unavailable text steps down to muted.
    final ink = enabled ? AppColors.text : AppColors.textMuted;
    const meta = AppColors.textMuted;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppMotion.quick,
          padding: ProfileMenuItemTile._padding,
          decoration: BoxDecoration(
            color: filled ? AppColors.band : Colors.transparent,
            borderRadius: AppRadius.controlAll,
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CrispText(
                      widget.profile.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.caption.copyWith(
                        color: ink,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    CrispText(
                      DictationProfileUiMapper.subtitleFor(
                        widget.profile,
                        isKeyBlocked: widget.isKeyBlocked,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.caption.copyWith(color: meta),
                    ),
                  ],
                ),
              ),
              if (widget.onEdit != null)
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onEdit,
                    child: const Padding(
                      padding: EdgeInsetsDirectional.only(
                        start: ProfileMenuItemTile._editPadStart,
                      ),
                      child: Icon(
                        AppIcons.pencil,
                        size: AppSizes.smallIconSize,
                        color: AppColors.textMuted,
                      ),
                    ),
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
    );
  }
}
