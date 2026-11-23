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
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    // This row is never "selected", so keyboard focus can share the hover
    // fill without being mistaken for the current style.
    final lit = _isHovered || _isFocused;
    final ink = lit ? AppColors.text : AppColors.textMuted;

    return Semantics(
      button: true,
      label: 'Add a custom style',
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (on) => setState(() => _isHovered = on),
        onShowFocusHighlight: (on) => setState(() => _isFocused = on),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) => widget.onTap(),
          ),
        },
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: AppMotion.quick,
            padding: AddCustomProfileTile._padding,
            decoration: BoxDecoration(
              color: lit ? AppColors.band : Colors.transparent,
              borderRadius: AppRadius.controlAll,
              border: const Border(top: BorderSide(color: AppColors.rule)),
            ),
            child: ExcludeSemantics(
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
        ),
      ),
    );
  }
}
