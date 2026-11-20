import 'package:material_ui/material_ui.dart';

import 'package:flutter_client/infrastructure/theme/app_theme.dart';

/// Compact select field in the style of the app's glass menus (the profile
/// picker): a filled trigger and a dark glass panel of short rows, with the
/// selected row checked.
///
/// Text styles derive from the theme, so the app font (Lexend) applies.
/// Material's DropdownButton replaces the inherited text style with whatever
/// `style` it is given, which dropped the font to the platform default.
class GlassDropdown<T> extends StatefulWidget {
  const GlassDropdown({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
  });

  final List<GlassDropdownItem<T>> items;
  final T value;

  /// Called with the chosen value. Null disables the field.
  final ValueChanged<T>? onChanged;

  static const double _fontSize = 13;
  static const double _triggerHeight = 36;
  static const double _itemHeight = 32;
  static const double _arrowSize = 18;
  static const double _checkSize = 14;
  static const double _menuMaxHeight = 240;
  static const double _menuGap = 4;
  static const double _menuElevation = 8;
  static const Color _menuColor = Color(0xF518181F);
  static const double _menuBorderAlpha = 0.16;
  static const double _hoverAlpha = 0.06;
  static const double _selectedAlpha = 0.08;
  static const BorderRadius _fieldRadius = BorderRadius.all(Radius.circular(8));
  static const BorderRadius _menuRadius = BorderRadius.all(Radius.circular(10));
  static const BorderRadius _itemRadius = BorderRadius.all(Radius.circular(7));

  @override
  State<GlassDropdown<T>> createState() => _GlassDropdownState<T>();
}

class _GlassDropdownState<T> extends State<GlassDropdown<T>> {
  final MenuController _menu = MenuController();

  void _toggleMenu() => _menu.isOpen ? _menu.close() : _menu.open();

  @override
  Widget build(BuildContext context) {
    final bodyStyle =
        Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
    final textStyle = bodyStyle.copyWith(fontSize: GlassDropdown._fontSize);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        return MenuAnchor(
          controller: _menu,
          alignmentOffset: const Offset(0, GlassDropdown._menuGap),
          style: MenuStyle(
            backgroundColor: const WidgetStatePropertyAll(
              GlassDropdown._menuColor,
            ),
            surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
            shadowColor: const WidgetStatePropertyAll(Colors.black),
            elevation: const WidgetStatePropertyAll(
              GlassDropdown._menuElevation,
            ),
            padding: const WidgetStatePropertyAll(EdgeInsets.all(4)),
            minimumSize: WidgetStatePropertyAll(Size(width, 0)),
            maximumSize: WidgetStatePropertyAll(
              Size(width, GlassDropdown._menuMaxHeight),
            ),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: GlassDropdown._menuRadius,
                side: BorderSide(
                  color: Colors.white.withValues(
                    alpha: GlassDropdown._menuBorderAlpha,
                  ),
                ),
              ),
            ),
          ),
          menuChildren: [
            for (final item in widget.items) _buildItem(item, textStyle),
          ],
          builder: (context, menu, _) => _buildTrigger(menu, textStyle),
        );
      },
    );
  }

  Widget _buildTrigger(MenuController menu, TextStyle textStyle) {
    final isEnabled = widget.onChanged != null;
    final selected = widget.items
        .where((item) => item.value == widget.value)
        .firstOrNull;

    return Material(
      color: Colors.black26,
      borderRadius: GlassDropdown._fieldRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isEnabled ? _toggleMenu : null,
        child: SizedBox(
          height: GlassDropdown._triggerHeight,
          child: Padding(
            padding: const EdgeInsets.only(left: 12, right: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    selected?.label ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textStyle.copyWith(
                      color: isEnabled ? Colors.white : Colors.white38,
                    ),
                  ),
                ),
                Icon(
                  menu.isOpen
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: GlassDropdown._arrowSize,
                  color: isEnabled ? Colors.white38 : Colors.white10,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildItem(GlassDropdownItem<T> item, TextStyle textStyle) {
    final isSelected = item.value == widget.value;

    return MenuItemButton(
      onPressed: () => widget.onChanged?.call(item.value),
      trailingIcon: isSelected
          ? const Icon(
              Icons.check,
              size: GlassDropdown._checkSize,
              color: AppTheme.crimsonPrimary,
            )
          : null,
      style: ButtonStyle(
        // Pin the row height: desktop themes default to compact density, and
        // touch platforms pad tap targets to 48 px.
        visualDensity: VisualDensity.standard,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        minimumSize: const WidgetStatePropertyAll(
          Size(0, GlassDropdown._itemHeight),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 10),
        ),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: GlassDropdown._itemRadius),
        ),
        backgroundColor: WidgetStatePropertyAll(
          isSelected
              ? Colors.white.withValues(alpha: GlassDropdown._selectedAlpha)
              : Colors.transparent,
        ),
        overlayColor: WidgetStatePropertyAll(
          Colors.white.withValues(alpha: GlassDropdown._hoverAlpha),
        ),
        foregroundColor: WidgetStatePropertyAll(
          isSelected ? Colors.white : Colors.white70,
        ),
        textStyle: WidgetStatePropertyAll(textStyle),
      ),
      child: Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

/// One option in a [GlassDropdown].
class GlassDropdownItem<T> {
  const GlassDropdownItem({required this.value, required this.label});

  final T value;
  final String label;
}
