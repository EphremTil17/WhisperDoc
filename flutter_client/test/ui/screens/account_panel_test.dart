import 'package:flutter_client/ui/screens/account_panel.dart';
import 'package:flutter_client/ui/shared/widgets/app_button.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';

import '../../orchestrators/home_orchestrator.dart';

void main() {
  group('AccountPanel', () {
    testWidgets('Groq with a key: masked key, model, and a way to remove it', (
      tester,
    ) async {
      final account = HomeOrchestrator(tester);
      when(
        () => account.settings.cachedGroqApiKey,
      ).thenReturn('gsk_abcdefghijklmnop3f2a');
      await account.pumpPanel(const AccountPanel());

      expect(find.text('Groq Cloud'), findsOneWidget);
      expect(find.text('Transcribing with your API key'), findsOneWidget);
      expect(find.text('gsk_…3f2a'), findsOneWidget);
      expect(find.text('Large v3 Turbo'), findsOneWidget);
      expect(find.text('Auto-detect'), findsOneWidget);
      expect(find.text('Remove API key'), findsOneWidget);
    });

    testWidgets('Groq without a key asks for one and offers nothing to remove', (
      tester,
    ) async {
      final account = HomeOrchestrator(tester)..removeGroqKey();
      await account.pumpPanel(const AccountPanel());

      expect(find.text('Add your API key to start'), findsOneWidget);
      expect(find.text('Not set'), findsOneWidget);
      expect(find.text('Remove API key'), findsNothing);
    });

    testWidgets('self-hosted and signed out offers sign-in', (tester) async {
      final account = HomeOrchestrator(tester);
      when(() => account.settings.isGroqMode).thenReturn(false);
      await account.pumpPanel(const AccountPanel());

      expect(find.text('WhisperDoc server'), findsOneWidget);
      expect(find.text('Sign in to start'), findsOneWidget);
      expect(find.text('whisper.example.com'), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);
      expect(find.text('Sign out'), findsNothing);
    });

    testWidgets('an available update names the version and offers Update', (
      tester,
    ) async {
      final account = HomeOrchestrator(tester)..offerUpdate();
      await account.pumpPanel(const AccountPanel());

      expect(find.text('Version 3.1.0'), findsOneWidget);
      expect(find.text('3.2.0 is available'), findsOneWidget);
      expect(find.widgetWithText(AppButton, 'Update'), findsOneWidget);
    });

    testWidgets('language is picked by name', (tester) async {
      final account = HomeOrchestrator(tester);
      when(
        () => account.settings.setGroqLanguage(any()),
      ).thenAnswer((_) => Future.value());
      await account.pumpPanel(const AccountPanel());

      await tester.tap(find.text('Language'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('French'), 200);
      await tester.tap(find.text('French'));
      await tester.pumpAndSettle();

      verify(() => account.settings.setGroqLanguage('fr')).called(1);
    });

    testWidgets('a server address that is not a WebSocket cannot be saved', (
      tester,
    ) async {
      final account = HomeOrchestrator(tester);
      when(() => account.settings.isGroqMode).thenReturn(false);
      await account.pumpPanel(const AccountPanel());

      await tester.tap(find.text('Server'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'http://example.com');
      await tester.pump();

      expect(find.text('Use a ws:// or wss:// address'), findsOneWidget);
      final save = tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Save'),
      );
      expect(save.onPressed, isNull);
    });
  });
}
