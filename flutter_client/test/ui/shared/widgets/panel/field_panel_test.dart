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

    testWidgets('a check runs before saving: while it runs Save says so, and a '
        'rejection is shown with nothing saved', (tester) async {
      final verdict = Completer<String?>();
      final saved = <String>[];
      await pumpOverPage(
        tester,
        FieldPanel(
          title: title,
          label: 'Model',
          initialValue: 'acme/x',
          check: (_) => verdict.future,
          onSave: (value) async => saved.add(value),
        ),
      );

      final save = saveButton();
      await tester.tap(save);
      await tester.pump();
      expect(find.widgetWithText(AppButton, 'Checking…'), findsOneWidget);

      verdict.complete('No such model.');
      await tester.pumpAndSettle();

      expect(find.text('No such model.'), findsOneWidget);
      expect(saved, isEmpty);
      expect(find.byType(FieldPanel), findsOneWidget);
      expect(tester.widget<AppButton>(save).onPressed, isNotNull);
    });

    testWidgets('a value the check accepts is saved', (tester) async {
      final saved = <String>[];
      await pumpOverPage(
        tester,
        FieldPanel(
          title: title,
          label: 'Model',
          initialValue: 'acme/x',
          check: (_) async => null,
          onSave: (value) async => saved.add(value),
        ),
      );

      await tester.tap(saveButton());
      await tester.pumpAndSettle();

      expect(saved, ['acme/x']);
      expect(find.text('open'), findsOneWidget);
    });
  });
}
