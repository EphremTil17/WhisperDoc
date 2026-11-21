import 'package:material_ui/material_ui.dart';

import 'package:flutter_client/infrastructure/theme/app_icons.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';

/// Select field in the Captions style: a ruled field on the ground and a flat
/// raised menu of short rows, with the selected row checked.
///
/// Text styles derive from the theme, so the app font (Lexend) applies.
/// Material's DropdownButton replaces the inherited text style with whatever
/// `style` it is given, which dropped the font to the platform default.
class AppDropdown<T> extends StatefulWidget {
  const AppDropdown({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
  });

  final List<AppDropdownItem<T>> items;
  final T value;

  /// Called with the chosen value. Null disables the field.
  final ValueChanged<T>? onChanged;

  static const double _itemHeight = 36;
  static const double _menuMaxHeight = 240;
  static const double _menuGap = 4;

  @override
  State<AppDropdown<T>> createState() => _AppDropdownState<T>();
}

class _AppDropdownState<T> extends State<AppDropdown<T>> {
  final MenuController _menu = MenuController();

  void _toggleMenu() => _menu.isOpen ? _menu.close() : _menu.open();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        return MenuAnchor(
          controller: _menu,
          alignmentOffset: const Offset(0, AppDropdown._menuGap),
          style: MenuStyle(
            backgroundColor: const WidgetStatePropertyAll(AppColors.surface),
            surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
            elevation: const WidgetStatePropertyAll(0),
            padding: const WidgetStatePropertyAll(EdgeInsets.all(AppSpace.xs)),
            minimumSize: WidgetStatePropertyAll(Size(width, 0)),
            maximumSize: WidgetStatePropertyAll(
              Size(width, AppDropdown._menuMaxHeight),
            ),
            shape: const WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: AppRadius.controlAll,
                side: BorderSide(color: AppColors.rule),
              ),
            ),
          ),
          menuChildren: [
            for (final item in widget.items) _buildItem(item),
          ],
          builder: (context, menu, _) => _buildTrigger(menu),
        );
      },
    );
  }

  Widget _buildTrigger(MenuController menu) {
    final isEnabled = widget.onChanged != null;
    final selected = widget.items
        .where((item) => item.value == widget.value)
        .firstOrNull;

    return Material(
      color: AppColors.ground,
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadius.controlAll,
        side: BorderSide(color: AppColors.rule),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isEnabled ? _toggleMenu : null,
        hoverColor: AppColors.band,
        splashFactory: NoSplash.splashFactory,
        child: SizedBox(
          height: AppSizes.controlHeight,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(
              start: AppSpace.md,
              end: AppSpace.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    selected?.label ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.body.copyWith(
                      color: isEnabled ? AppColors.text : AppColors.textMuted,
                    ),
                  ),
                ),
                Icon(
                  menu.isOpen ? AppIcons.chevronUp : AppIcons.chevronDown,
                  size: AppSizes.smallIconSize,
                  color: isEnabled ? AppColors.textMuted : AppColors.iconFaint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildItem(AppDropdownItem<T> item) {
    final isSelected = item.value == widget.value;

    return MenuItemButton(
      onPressed: () => widget.onChanged?.call(item.value),
      trailingIcon: isSelected
          ? const Icon(
              AppIcons.check,
              size: AppSizes.smallIconSize,
              color: AppColors.text,
            )
          : null,
      style: ButtonStyle(
        // Pin the row height: desktop themes default to compact density, and
        // touch platforms pad tap targets to 48 px.
        visualDensity: VisualDensity.standard,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        minimumSize: const WidgetStatePropertyAll(
          Size(0, AppDropdown._itemHeight),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: AppSpace.md),
        ),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: AppRadius.controlAll),
        ),
        backgroundColor: WidgetStatePropertyAll(
          isSelected ? AppColors.band : Colors.transparent,
        ),
        overlayColor: const WidgetStatePropertyAll(AppColors.band),
        foregroundColor: WidgetStatePropertyAll(
          isSelected ? AppColors.text : AppColors.textMuted,
        ),
        textStyle: const WidgetStatePropertyAll(AppType.body),
      ),
      child: Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

/// One option in a [AppDropdown].
class AppDropdownItem<T> {
  const AppDropdownItem({required this.value, required this.label});

  final T value;
  final String label;
}
