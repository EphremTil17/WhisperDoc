// Mocktail matchers must be invoked inline to register each argument matcher.
// ignore_for_file: prefer-moving-to-variable
import 'dart:async';

import 'package:flutter_client/infrastructure/theme/app_icons.dart';
import 'package:flutter_client/ui/screens/settings/widgets/microphone_panel.dart';
import 'package:flutter_client/ui/shared/widgets/panel/app_panel.dart';
import 'package:flutter_client/ui/shared/widgets/panel/panel_row.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:record/record.dart';

import '../../../orchestrators/home_orchestrator.dart';

void main() {
  const usb = InputDevice(id: 'mic-usb', label: 'USB Microphone');
  const headset = InputDevice(id: 'mic-headset', label: 'Headset');

  group('MicrophonePanel', () {
    /// Opens the panel from a launcher so picking a device can go back.
    Future<HomeOrchestrator> open(
      WidgetTester tester, {
      Future<List<InputDevice>>? devices,
      String? current,
    }) async {
      final home = HomeOrchestrator(tester);
      when(home.audio.listInputDevices)
          .thenAnswer((_) => devices ?? Future.value(const [usb, headset]));
      when(() => home.settings.microphoneId).thenReturn(current);
      when(() => home.settings.setMicrophoneSelection(any(), any()))
          .thenAnswer((_) => Future.value());
      await home.pumpPanel(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => unawaited(
                AppPanel.push<void>(context, const MicrophonePanel()),
              ),
              child: const Text('Open microphones'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open microphones'));
      await tester.pumpAndSettle();

      return home;
    }

    /// The row labelled [label] carries the check mark.
    Finder checked(String label) => find.descendant(
      of: find.widgetWithText(PanelRow, label),
      matching: find.byIcon(AppIcons.check),
    );

    testWidgets('lists the system default and every input', (tester) async {
      await open(tester, current: 'mic-headset');

      expect(find.text('System default'), findsOneWidget);
      expect(find.text('USB Microphone'), findsOneWidget);
      expect(find.text('Headset'), findsOneWidget);
      expect(checked('Headset'), findsOneWidget);
      expect(find.byIcon(AppIcons.check), findsOneWidget);
    });

    testWidgets('says it is looking while devices load', (tester) async {
      final pending = Completer<List<InputDevice>>();
      await open(tester, devices: pending.future);

      final looking = find.text('[ looking for microphones ]');
      expect(looking, findsOneWidget);

      pending.complete(const [usb]);
      await tester.pumpAndSettle();
      expect(looking, findsNothing);
      expect(find.text('USB Microphone'), findsOneWidget);
    });

    testWidgets('Refresh lists a microphone plugged in since opening', (
      tester,
    ) async {
      final home = await open(tester, devices: Future.value(const [usb]));
      expect(find.text('Headset'), findsNothing);

      when(home.audio.listInputDevices)
          .thenAnswer((_) => Future.value(const [usb, headset]));
      await tester.tap(find.byTooltip('Refresh devices'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Headset'), findsOneWidget);
    });

    testWidgets('says so when there are no inputs', (tester) async {
      await open(tester, devices: Future.value(const []));

      expect(find.text('[ no microphones found ]'), findsOneWidget);
      expect(checked('System default'), findsOneWidget);
    });

    testWidgets('a remembered input that is gone shows as the default', (
      tester,
    ) async {
      await open(tester, current: 'mic-unplugged');

      expect(checked('System default'), findsOneWidget);
      expect(find.byIcon(AppIcons.check), findsOneWidget);
    });

    testWidgets('picking an input saves it with its name and goes back', (
      tester,
    ) async {
      final home = await open(tester);

      await tester.tap(find.text('Headset'));
      await tester.pumpAndSettle();

      verify(
        () => home.settings.setMicrophoneSelection('mic-headset', 'Headset'),
      ).called(1);
      expect(find.text('Open microphones'), findsOneWidget);
    });

    testWidgets('picking the system default clears the choice', (tester) async {
      final home = await open(tester, current: 'mic-usb');

      await tester.tap(find.text('System default'));
      await tester.pumpAndSettle();

      final cleared = verify(
        () => home.settings.setMicrophoneSelection(null, null),
      );
      expect(cleared.callCount, 1);
    });
  });
}
