import 'package:flutter_client/ui/screens/settings_panel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';

import '../../orchestrators/home_orchestrator.dart';

void main() {
  group('SettingsPanel', () {
    testWidgets('shows each setting with its current value', (tester) async {
      final settings = HomeOrchestrator(tester);
      await settings.pumpPanel(const SettingsPanel());

      expect(find.text('System default'), findsOneWidget);
      expect(find.text('Ctrl Q'), findsOneWidget);
      expect(find.text('Show level meter'), findsOneWidget);
      const toggles = 4; // meter, copy, paste, moving background
      expect(find.byType(Switch), findsNWidgets(toggles));
    });

    testWidgets('tapping a toggle row flips the setting', (tester) async {
      final settings = HomeOrchestrator(tester);
      when(
        () => settings.settings.setAutoCopy(any()),
      ).thenAnswer((_) => Future.value());
      await settings.pumpPanel(const SettingsPanel());

      await tester.tap(find.text('Copy to clipboard'));

      final flipped = verify(() => settings.settings.setAutoCopy(false));
      expect(flipped.callCount, 1);
    });

    testWidgets('the background can be held still', (tester) async {
      final settings = HomeOrchestrator(tester);
      when(
        () => settings.settings.setAnimateBackground(any()),
      ).thenAnswer((_) => Future.value());
      await settings.pumpPanel(const SettingsPanel());

      expect(
        find.text('Off keeps a still map, for slower computers'),
        findsOneWidget,
      );
      await tester.tap(find.text('Moving background'));

      verify(() => settings.settings.setAnimateBackground(false)).called(1);
    });

    testWidgets('paste is unavailable until copy is on', (tester) async {
      final settings = HomeOrchestrator(tester);
      when(() => settings.settings.autoCopy).thenReturn(false);
      await settings.pumpPanel(const SettingsPanel());

      expect(find.text('Needs Copy to clipboard'), findsOneWidget);
      await tester.tap(find.text('Paste where your cursor is'));
      verifyNever(() => settings.settings.setAutoPaste(any()));
    });

    testWidgets('the microphone is locked while recording', (tester) async {
      final settings = HomeOrchestrator(tester)..startRecording();
      await settings.pumpPanel(const SettingsPanel());

      await tester.tap(find.text('Microphone'));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsPanel), findsOneWidget);
      expect(find.text('Refresh devices'), findsNothing);
    });
  });
}
