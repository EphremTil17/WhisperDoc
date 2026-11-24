// Each tester.pumpAndSettle() advances the UI past a different tap, so the
// repeats have no shared value to hold.
// ignore_for_file: prefer-moving-to-variable
import 'package:flutter_client/ui/screens/account_panel.dart';
import 'package:flutter_client/ui/shared/widgets/app_button.dart';
import 'package:flutter_client/ui/shared/widgets/panel/field_panel.dart';
import 'package:flutter_client/ui/shared/widgets/panel/panel_row.dart';
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
      when(() => account.settings.cachedGroqApiKey)
          .thenReturn('gsk_abcdefghijklmnop3f2a');
      await account.pumpPanel(const AccountPanel());

      const selectorAndIdentity = 2;
      expect(find.text('Groq'), findsNWidgets(selectorAndIdentity));
      expect(find.text('Transcribing with your API key'), findsOneWidget);
      expect(find.text('gsk_…3f2a'), findsOneWidget);
      expect(find.text('Large v3 Turbo'), findsOneWidget);
      expect(find.text('Auto-detect'), findsOneWidget);
      expect(find.text('Remove API key'), findsOneWidget);
    });

    testWidgets(
      'Groq without a key asks for one and offers nothing to remove',
      (tester) async {
        final account = HomeOrchestrator(tester)..removeGroqKey();
        await account.pumpPanel(const AccountPanel());

        expect(find.text('Add your API key to start'), findsOneWidget);
        expect(find.text('Not set'), findsOneWidget);
        expect(find.text('Remove API key'), findsNothing);
      },
    );

    testWidgets('self-hosted and signed out offers sign-in', (tester) async {
      final account = HomeOrchestrator(tester)..useServer();
      await account.pumpPanel(const AccountPanel());

      expect(find.text('WhisperDoc server'), findsOneWidget);
      expect(find.text('Sign in to start'), findsOneWidget);
      expect(find.text('whisper.example.com'), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);
      expect(find.text('Sign out'), findsNothing);
    });

    testWidgets('a failed sign-in says so instead of doing nothing', (
      tester,
    ) async {
      final account = HomeOrchestrator(tester)..useServer();
      when(() => account.profile.signIn()).thenThrow(StateError('no issuer'));
      await account.pumpPanel(const AccountPanel());

      await tester.tap(find.text('Sign in'));
      await tester.pump();

      expect(
        find.text("Couldn't sign in. Details are in Logs."),
        findsOneWidget,
      );
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
      const scrollStep = 200.0;
      final account = HomeOrchestrator(tester);
      when(() => account.settings.setGroqLanguage(any()))
          .thenAnswer((_) => Future.value());
      await account.pumpPanel(const AccountPanel());

      final french = find.text('French');
      await tester.tap(find.text('Language'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(french, scrollStep);
      await tester.tap(french);
      await tester.pumpAndSettle();

      final picked = verify(() => account.settings.setGroqLanguage('fr'));
      expect(picked.callCount, 1);
    });

    testWidgets('a server address that is not a WebSocket cannot be saved', (
      tester,
    ) async {
      final account = HomeOrchestrator(tester)..useServer();
      await account.pumpPanel(const AccountPanel());

      await tester.tap(find.text('Server'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'ftp://example.com');
      await tester.pump();

      expect(find.text('Use a wss:// or https:// address'), findsOneWidget);
      final save = tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Save'),
      );
      expect(save.onPressed, isNull);
    });

    testWidgets('the default https:// address is accepted as wss://', (
      tester,
    ) async {
      final account = HomeOrchestrator(tester)..useServer();
      await account.pumpPanel(const AccountPanel());

      await tester.tap(find.text('Server'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'https://example.com');
      await tester.pump();

      expect(find.textContaining('Use '), findsNothing);
      final save = tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Save'),
      );
      expect(save.onPressed, isNotNull);
    });

    testWidgets(
      'public ws:// is blocked inline while wss:// and local ws:// save',
      (tester) async {
        final account = HomeOrchestrator(tester)..useServer();
        await account.pumpPanel(const AccountPanel());

        final field = find.byType(TextField);
        final saveButton = find.widgetWithText(AppButton, 'Save');
        Future<bool> canSave(String address) async {
          await tester.enterText(field, address);
          await tester.pump();

          return tester.widget<AppButton>(saveButton).onPressed != null;
        }

        await tester.tap(find.text('Server'));
        await tester.pumpAndSettle();

        expect(await canSave('ws://example.com/ws'), isFalse);
        expect(
          find.text('Use wss:// for remote servers (ws:// is local only)'),
          findsOneWidget,
        );
        expect(await canSave('ws://127.evil.example/ws'), isFalse);
        expect(await canSave('ws://localhost:9989/ws'), isTrue);
        expect(await canSave('wss://whisper.example.com/ws'), isTrue);
      },
    );

    testWidgets('rejects non-HTTPS avatar URLs and falls back to initial', (
      tester,
    ) async {
      final account = HomeOrchestrator(tester)..useServer();
      when(() => account.profile.isAuthenticated).thenReturn(true);
      when(() => account.profile.currentUser).thenReturn({
        'id': 'sub-1',
        'name': 'Ada Lovelace',
        'email': 'ada@example.com',
        'picture': 'http://insecure.example/avatar.png',
      });
      await account.pumpPanel(const AccountPanel());

      expect(find.byType(Image), findsNothing);
      expect(find.text('A'), findsOneWidget);
    });

    testWidgets(
      'secret field starts masked, toggles visibility, and trims on save',
      (tester) async {
        final account = HomeOrchestrator(tester)..removeGroqKey();
        when(() => account.settings.setGroqApiKey(any()))
            .thenAnswer((_) => Future.value());
        await account.pumpPanel(const AccountPanel());

        final textFieldFinder = find.byType(TextField);
        bool isObscured() =>
            tester.widget<TextField>(textFieldFinder).obscureText;
        Future<bool> isObscuredAfterTapping(String tooltip) async {
          await tester.tap(find.byTooltip(tooltip));
          await tester.pump();

          return isObscured();
        }

        await tester.tap(find.text('API key'));
        await tester.pumpAndSettle();
        expect(isObscured(), isTrue);
        expect(await isObscuredAfterTapping('Show'), isFalse);
        expect(await isObscuredAfterTapping('Hide'), isTrue);

        await tester.enterText(textFieldFinder, '  gsk_test_trimmed_key  ');
        await tester.pump();
        await tester.tap(find.widgetWithText(AppButton, 'Save'));
        await tester.pumpAndSettle();

        final saved = verify(
          () => account.settings.setGroqApiKey('gsk_test_trimmed_key'),
        );
        expect(saved.callCount, 1);
      },
    );

    testWidgets('connection rows lock while a dictation runs', (tester) async {
      final account = HomeOrchestrator(tester)
        ..useServer()
        ..startRecording();
      when(() => account.profile.isAuthenticated).thenReturn(true);
      await account.pumpPanel(const AccountPanel());

      const lockedRows = 2; // Server and Developer key; signed in, no Sign in
      expect(
        find.text(PanelRow.lockedWhileRecording),
        findsNWidgets(lockedRows),
      );
      await tester.tap(find.text('Server'));
      await tester.pumpAndSettle();
      expect(find.byType(FieldPanel), findsNothing, reason: 'row is locked');

      await tester.tap(find.text('Sign out'));
      verifyNever(() => account.profile.signOut());
    });

    testWidgets('Sign out signs out when no dictation runs', (tester) async {
      final account = HomeOrchestrator(tester)..useServer();
      when(() => account.profile.isAuthenticated).thenReturn(true);
      when(account.profile.signOut).thenAnswer((_) => Future.value());
      await account.pumpPanel(const AccountPanel());

      await tester.tap(find.text('Sign out'));

      final signedOut = verify(account.profile.signOut);
      expect(signedOut.callCount, 1);
    });

    testWidgets('Remove API key asks first and clears the key only on yes', (
      tester,
    ) async {
      final account = HomeOrchestrator(tester);
      when(() => account.settings.cachedGroqApiKey)
          .thenReturn('gsk_abcdefghijklmnop3f2a');
      when(() => account.settings.setGroqApiKey(any()))
          .thenAnswer((_) => Future.value());
      await account.pumpPanel(const AccountPanel());

      await tester.tap(find.text('Remove API key'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(AppButton, 'Cancel'));
      await tester.pumpAndSettle();
      verifyNever(() => account.settings.setGroqApiKey(any()));

      await tester.tap(find.text('Remove API key'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(AppButton, 'Remove'));
      await tester.pumpAndSettle();
      final cleared = verify(() => account.settings.setGroqApiKey(''));
      expect(cleared.callCount, 1);
    });
  });
}
