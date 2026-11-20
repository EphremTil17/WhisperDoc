import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:flutter_client/ui/shared/widgets/glass_dropdown.dart';

const _themeFont = 'ThemeFont';

const _items = [
  GlassDropdownItem<String?>(
    value: null,
    label: 'Default (System Voice Input)',
  ),
  GlassDropdownItem<String?>(
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
            child: GlassDropdown<String?>(
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

/// The style a label is actually painted with, after inherited merging.
TextStyle? _paintedStyle(WidgetTester tester, String label) {
  final paragraph = tester.widget<RichText>(
    find.descendant(of: find.text(label), matching: find.byType(RichText)),
  );

  return paragraph.text.style;
}

void main() {
  group('GlassDropdown', () {
    testWidgets('shows the selected label in the theme font', (tester) async {
      await _pump(tester, value: 'rode', onChanged: (_) {});

      expect(find.text('Microphone (RODE VideoMic)'), findsOneWidget);
      expect(
        _paintedStyle(tester, 'Microphone (RODE VideoMic)')?.fontFamily,
        _themeFont,
      );
    });

    testWidgets('menu rows are compact and use the theme font', (tester) async {
      // Regression: Material's DropdownButton replaced the inherited style, so
      // menu text fell back to the platform font in 48 px rows.
      await _pump(tester, onChanged: (_) {});
      await tester.tap(find.byType(GlassDropdown<String?>));
      await tester.pumpAndSettle();

      final rows = find.byType(MenuItemButton);
      expect(rows, findsNWidgets(_items.length));
      expect(tester.getSize(rows.first).height, 32);
      expect(
        _paintedStyle(tester, 'Microphone (RODE VideoMic)')?.fontFamily,
        _themeFont,
      );
    });

    testWidgets('choosing an item reports it and closes the menu', (
      tester,
    ) async {
      final chosen = <String?>[];
      await _pump(tester, onChanged: chosen.add);

      await tester.tap(find.byType(GlassDropdown<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Microphone (RODE VideoMic)').last);
      await tester.pumpAndSettle();

      expect(chosen, ['rode']);
      expect(find.byType(MenuItemButton), findsNothing);
    });

    testWidgets('a disabled field does not open', (tester) async {
      await _pump(tester);

      await tester.tap(find.byType(GlassDropdown<String?>));
      await tester.pumpAndSettle();

      expect(find.byType(MenuItemButton), findsNothing);
    });
  });
}
