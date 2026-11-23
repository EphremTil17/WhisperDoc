import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_client/ui/screens/settings/widgets/hotkey_recorder_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:win32/win32.dart';

import '../../../orchestrators/home_orchestrator.dart';

void main() {
  // Win32 RegisterHotKey modifier flags.
  const modAlt = 0x0001;
  const modControl = 0x0002;
  const modShift = 0x0004;

  group('HotkeyRecorderDialog', () {
    /// Opens the dialog over a launcher; [closed] completes with what it
    /// popped once it is gone.
    Future<Future<HotkeyBinding?>> open(WidgetTester tester) async {
      final closed = Completer<HotkeyBinding?>();
      Future<void> record(BuildContext context) async {
        final picked = await showDialog<HotkeyBinding>(
          context: context,
          builder: (_) => const HotkeyRecorderDialog(),
        );
        closed.complete(picked);
      }

      await HomeOrchestrator(tester).pumpPanel(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => unawaited(record(context)),
              child: const Text('Record shortcut'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Record shortcut'));
      await tester.pumpAndSettle();

      return closed.future;
    }

    /// Holds [modifiers], presses [key], then lets go.
    Future<void> press(
      WidgetTester tester,
      List<LogicalKeyboardKey> modifiers,
      LogicalKeyboardKey key,
    ) async {
      for (final modifier in modifiers) {
        await tester.sendKeyDownEvent(modifier);
      }
      await tester.sendKeyEvent(key);
      for (final modifier in modifiers.reversed) {
        await tester.sendKeyUpEvent(modifier);
      }
      await tester.pump();
    }

    Future<void> save(WidgetTester tester) async {
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
    }

    testWidgets('waits for keys, with nothing to save yet', (tester) async {
      final result = await open(tester);

      expect(find.text('[ waiting for keys ]'), findsOneWidget);
      await save(tester);

      expect(find.text('Shortcut'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await result, isNull);
    });

    testWidgets('records Ctrl+Shift and a letter', (tester) async {
      final result = await open(tester);

      await press(tester, [
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.shiftLeft,
      ], LogicalKeyboardKey.keyK);

      expect(find.text('Ctrl Shift K'), findsOneWidget);
      expect(find.text('[ waiting for keys ]'), findsNothing);
      await save(tester);
      final binding = await result;
      expect(binding?.display, 'Ctrl+Shift+K');
      expect(binding?.modifiers, modControl | modShift);
      expect(binding?.vKey, VK_K);
      expect(find.text('Shortcut'), findsNothing);
    });

    testWidgets('records Alt and a function key', (tester) async {
      final result = await open(tester);

      await press(tester, [LogicalKeyboardKey.altRight], LogicalKeyboardKey.f5);
      await save(tester);

      final binding = await result;
      expect(binding?.display, 'Alt+F5');
      expect(binding?.modifiers, modAlt);
      expect(binding?.vKey, VK_F5);
    });

    testWidgets('all three modifiers combine', (tester) async {
      final result = await open(tester);

      await press(tester, [
        LogicalKeyboardKey.shiftRight,
        LogicalKeyboardKey.altLeft,
        LogicalKeyboardKey.controlRight,
      ], LogicalKeyboardKey.keyQ);
      await save(tester);

      final binding = await result;
      expect(binding?.display, 'Ctrl+Alt+Shift+Q');
      expect(binding?.modifiers, modControl | modAlt | modShift);
    });

    testWidgets('a key without a modifier is not a shortcut', (tester) async {
      await open(tester);

      await press(tester, [], LogicalKeyboardKey.keyK);

      expect(find.text('[ waiting for keys ]'), findsOneWidget);
    });

    testWidgets('a modifier alone is not a shortcut', (tester) async {
      await open(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(find.text('[ waiting for keys ]'), findsOneWidget);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    });

    testWidgets('a key Windows cannot bind is ignored', (tester) async {
      await open(tester);

      await press(tester, [
        LogicalKeyboardKey.controlLeft,
      ], LogicalKeyboardKey.digit1);

      expect(find.text('[ waiting for keys ]'), findsOneWidget);
    });

    testWidgets('a new combination replaces the last one', (tester) async {
      final result = await open(tester);

      await press(tester, [
        LogicalKeyboardKey.controlLeft,
      ], LogicalKeyboardKey.keyA);
      await press(tester, [
        LogicalKeyboardKey.altLeft,
      ], LogicalKeyboardKey.keyB);
      await save(tester);

      expect((await result)?.display, 'Alt+B');
    });

    testWidgets('Esc cancels without a shortcut', (tester) async {
      final result = await open(tester);
      await press(tester, [
        LogicalKeyboardKey.controlLeft,
      ], LogicalKeyboardKey.keyK);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(await result, isNull);
      expect(find.text('Shortcut'), findsNothing);
      expect(find.text('Record shortcut'), findsOneWidget);
    });
  });
}
