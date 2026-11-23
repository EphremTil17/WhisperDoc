import 'dart:async';

import 'package:flutter_client/infrastructure/theme/app_theme.dart';
import 'package:flutter_client/ui/shared/widgets/app_button.dart';
import 'package:flutter_client/ui/shared/widgets/panel/field_panel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  const title = 'Server';

  /// Opens [panel] over a plain page so a pop is visible as the page coming
  /// back.
  Future<void> pumpOverPage(WidgetTester tester, FieldPanel panel) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => unawaited(
              Navigator.of(context)
                  .push<void>(MaterialPageRoute(builder: (_) => panel)),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder saveButton() => find.widgetWithText(AppButton, 'Save');

  group('FieldPanel', () {
    testWidgets('saving twice before the first finishes saves once', (
      tester,
    ) async {
      final pending = Completer<void>();
      var saves = 0;
      await pumpOverPage(
        tester,
        FieldPanel(
          title: title,
          label: 'Address',
          initialValue: 'wss://example.com/ws',
          onSave: (_) {
            saves++;

            return pending.future;
          },
        ),
      );

      final save = saveButton();
      await tester.tap(save);
      await tester.pump();
      expect(tester.widget<AppButton>(save).onPressed, isNull);

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(saves, 1);

      pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget, reason: 'one pop, to the page');
    });

    testWidgets('a failed save says so and stays open', (tester) async {
      await pumpOverPage(
        tester,
        FieldPanel(
          title: title,
          label: 'Address',
          initialValue: 'wss://example.com/ws',
          onSave: (_) => Future<void>.error(StateError('vault locked')),
        ),
      );

      final save = saveButton();
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(find.text("Couldn't save. Try again."), findsOneWidget);
      expect(find.byType(FieldPanel), findsOneWidget);
      expect(tester.widget<AppButton>(save).onPressed, isNotNull);
    });
  });
}
