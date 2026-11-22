import 'package:material_ui/material_ui.dart';
import 'package:flutter_client/infrastructure/theme/app_icons.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/ui/shared/widgets/crisp_text.dart';

/// The last row of the style menu: create a custom output style.
class AddCustomProfileTile extends StatefulWidget {
  const AddCustomProfileTile({required this.onTap, super.key});

  final VoidCallback onTap;

  static const EdgeInsets _padding = EdgeInsets.symmetric(
    horizontal: 10,
    vertical: AppSpace.sm,
  );

  @override
  State<AddCustomProfileTile> createState() => _AddCustomProfileTileState();
}

class _AddCustomProfileTileState extends State<AddCustomProfileTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final ink = _isHovered ? AppColors.text : AppColors.textMuted;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppMotion.quick,
          padding: AddCustomProfileTile._padding,
          decoration: BoxDecoration(
            color: _isHovered ? AppColors.band : Colors.transparent,
            borderRadius: AppRadius.controlAll,
            border: const Border(top: BorderSide(color: AppColors.rule)),
          ),
          child: Row(
            spacing: AppSpace.md,
            children: [
              Icon(AppIcons.plus, size: AppSizes.smallIconSize, color: ink),
              Flexible(
                child: CrispText(
                  'Custom Profile',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.caption.copyWith(
                    color: ink,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
