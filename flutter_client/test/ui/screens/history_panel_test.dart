import 'package:flutter_client/logic/models/history_entry.dart';
import 'package:flutter_client/ui/screens/history_panel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../orchestrators/home_orchestrator.dart';

void main() {
  group('HistoryPanel', () {
    const firstRevision = 1;
    const nextRevision = 2;
    const twoEntries = 2;

    /// An entry the controller decrypts to [text], or fails to when null.
    HistoryEntry entry(HomeOrchestrator home, DateTime at, String? text) {
      final made = HistoryEntry(
        encryptedText: 'gcm:${at.millisecondsSinceEpoch}',
        ivBase64: 'iv',
        timestamp: at,
      );
      final decrypt = when(() => home.recording.getDecryptedText(made));
      if (text == null) {
        decrypt.thenThrow(ArgumentError('Invalid or corrupted pad block'));
      } else {
        decrypt.thenReturn(text);
      }

      return made;
    }

    void showHistory(
      HomeOrchestrator home,
      List<HistoryEntry> entries, {
      int revision = firstRevision,
    }) {
      when(() => home.recording.historyRevision).thenReturn(revision);
      when(() => home.recording.history).thenReturn(entries);
    }

    testWidgets('no transcripts yet says so', (tester) async {
      final home = HomeOrchestrator(tester);
      showHistory(home, []);
      await home.pumpPanel(const HistoryPanel());

      expect(find.text('History'), findsOneWidget);
      expect(find.text('[ no transcripts yet ]'), findsOneWidget);
    });

    testWidgets('incognito explains why history is empty', (tester) async {
      final home = HomeOrchestrator(tester);
      showHistory(home, []);
      when(() => home.recording.incognitoMode).thenReturn(true);
      await home.pumpPanel(const HistoryPanel());

      expect(find.text('[ incognito · nothing is saved ]'), findsOneWidget);
      expect(find.text('[ no transcripts yet ]'), findsNothing);
    });

    testWidgets('shows each transcript with when it was made', (tester) async {
      final home = HomeOrchestrator(tester);
      showHistory(home, [
        entry(home, DateTime(2025, 11, 20, 14, 32), 'Follow up in two weeks'),
        entry(home, DateTime(2025, 3, 2, 9, 5), 'Patient reports no pain'),
      ]);
      await home.pumpPanel(const HistoryPanel());

      expect(find.text('Follow up in two weeks'), findsOneWidget);
      expect(find.text('20 Nov 14:32'), findsOneWidget);
      expect(find.text('Patient reports no pain'), findsOneWidget);
      expect(find.text('2 Mar 09:05'), findsOneWidget);
      expect(find.byTooltip('Copy'), findsNWidgets(twoEntries));
    });

    testWidgets('an unreadable entry says so and offers nothing to copy', (
      tester,
    ) async {
      final home = HomeOrchestrator(tester);
      showHistory(home, [
        entry(home, DateTime(2025, 11, 20, 14, 32), 'Readable note'),
        entry(home, DateTime(2025, 11, 19, 8), null),
      ]);
      await home.pumpPanel(const HistoryPanel());

      expect(find.text('Readable note'), findsOneWidget);
      expect(find.text("[ can't read this entry ]"), findsOneWidget);
      expect(find.byTooltip('Copy'), findsOneWidget);
    });

    testWidgets('each entry is decrypted once, not on every rebuild', (
      tester,
    ) async {
      final home = HomeOrchestrator(tester);
      final recording = home.recording;
      final readable = entry(home, DateTime(2025, 11, 20, 14, 32), 'Once');
      final broken = entry(home, DateTime(2025, 11, 19, 8), null);
      showHistory(home, [readable, broken]);
      await home.pumpPanel(const HistoryPanel());

      showHistory(home, [readable, broken], revision: nextRevision);
      recording.notifyListeners();
      await tester.pump();

      expect(find.text('Once'), findsOneWidget);
      verify(() => recording.getDecryptedText(readable)).called(1);
      verify(() => recording.getDecryptedText(broken)).called(1);
    });

    testWidgets('a new transcript appears when the history changes', (
      tester,
    ) async {
      final home = HomeOrchestrator(tester);
      final empty = find.text('[ no transcripts yet ]');
      showHistory(home, []);
      await home.pumpPanel(const HistoryPanel());
      expect(empty, findsOneWidget);

      showHistory(home, [
        entry(home, DateTime(2025, 11, 20, 14, 32), 'Just said'),
      ], revision: nextRevision);
      home.recording.notifyListeners();
      await tester.pump();

      expect(find.text('Just said'), findsOneWidget);
      expect(empty, findsNothing);
    });
  });
}
