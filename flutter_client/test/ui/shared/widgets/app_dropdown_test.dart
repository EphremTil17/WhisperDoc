import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/ui/shared/widgets/app_dropdown.dart';

const _themeFont = 'ThemeFont';

const _items = [
  AppDropdownItem<String?>(
    value: null,
    label: 'Default (System Voice Input)',
  ),
  AppDropdownItem<String?>(
    value: 'rode',
    label: 'Microphone (RODE VideoMic)',
  ),
];

Future<void> _pump(
  WidgetTester tester, {
  String? value,
  ValueChanged<String?>? onChanged,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: _themeFont),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            child: AppDropdown<String?>(
              items: _items,
              value: value,
              onChanged: onChanged,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Row height for menu items (the 36px row in the Captions control scale).
const _rowHeight = 36.0;

/// The style a label is actually painted with, after inherited merging.
TextStyle? _paintedStyle(WidgetTester tester, String label) {
  final paragraph = tester.widget<RichText>(
    find.descendant(of: find.text(label), matching: find.byType(RichText)),
  );

  return paragraph.text.style;
}

void main() {
  group('AppDropdown', () {
    testWidgets('shows the selected label in the app font', (tester) async {
      // The field sets the app's type style explicitly, so neither a theme
      // font nor Material's style replacement can drop it.
      await _pump(tester, value: 'rode', onChanged: (_) {});

      expect(find.text('Microphone (RODE VideoMic)'), findsOneWidget);
      expect(
        _paintedStyle(tester, 'Microphone (RODE VideoMic)')?.fontFamily,
        AppType.family,
      );
    });

    testWidgets('menu rows are compact and use the app font', (tester) async {
      // Regression: Material's DropdownButton replaced the inherited style, so
      // menu text fell back to the platform font in 48 px rows.
      await _pump(tester, onChanged: (_) {});
      await tester.tap(find.byType(AppDropdown<String?>));
      await tester.pumpAndSettle();

      final rows = find.byType(MenuItemButton);
      expect(rows, findsNWidgets(_items.length));
      expect(tester.getSize(rows.first).height, _rowHeight);
      expect(
        _paintedStyle(tester, 'Microphone (RODE VideoMic)')?.fontFamily,
        AppType.family,
      );
    });

    testWidgets('choosing an item reports it and closes the menu', (
      tester,
    ) async {
      final chosen = <String?>[];
      await _pump(tester, onChanged: chosen.add);

      await tester.tap(find.byType(AppDropdown<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Microphone (RODE VideoMic)').last);
      await tester.pumpAndSettle();

      expect(chosen, ['rode']);
      expect(find.byType(MenuItemButton), findsNothing);
    });

    testWidgets('a disabled field does not open', (tester) async {
      await _pump(tester);

      await tester.tap(find.byType(AppDropdown<String?>));
      await tester.pumpAndSettle();

      expect(find.byType(MenuItemButton), findsNothing);
    });
  });
}
