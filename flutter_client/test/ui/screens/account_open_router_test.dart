// Each tester.pumpAndSettle() advances the UI past a different tap, so the
// repeats have no shared value to hold.
// ignore_for_file: prefer-moving-to-variable
import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import 'package:flutter_client/logic/models/model_selection_problem.dart';
import 'package:flutter_client/logic/models/speech_model.dart';
import 'package:flutter_client/logic/models/transcription_source.dart';
import 'package:flutter_client/services/transcription/cloud_error.dart';
import 'package:flutter_client/ui/screens/account/open_router_model_panel.dart';
import 'package:flutter_client/ui/screens/account_panel.dart';
import 'package:flutter_client/ui/shared/widgets/app_button.dart';
import 'package:flutter_client/ui/shared/widgets/app_link.dart';
import 'package:flutter_client/ui/shared/widgets/panel/field_panel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';

import '../../orchestrators/home_orchestrator.dart';

void main() {
  // Real OpenRouter ids, so the bundled WER snapshot applies: 2.0%, 2.4%,
  // none, and 2.3%.
  const mai = SpeechModel(
    id: 'microsoft/mai-transcribe-2',
    fullName: 'Microsoft AI: MAI-Transcribe 2',
    zdr: true,
  );
  final retiring = SpeechModel(
    id: 'microsoft/mai-transcribe-1.5',
    fullName: 'Microsoft AI: MAI-Transcribe 1.5',
    zdr: true,
    retiresOn: DateTime.parse('2026-12-22'),
  );
  const unranked = SpeechModel(
    id: 'qwen/qwen3-asr-1.7b',
    fullName: 'Qwen: Qwen3 ASR 1.7B',
    zdr: true,
  );
  const grok = SpeechModel(
    id: 'x-ai/grok-stt-2.0',
    fullName: 'SpaceXSI: Grok STT 2.0',
    zdr: false,
  );

  setUpAll(() {
    registerFallbackValue(TranscriptionSource.server);
  });

  group('Source selector', () {
    testWidgets('offers all three sources and marks the active one', (
      tester,
    ) async {
      final account = HomeOrchestrator(tester);
      await account.pumpPanel(const AccountPanel());

      for (final label in ['Self-hosted', 'OpenRouter']) {
        expect(find.text(label), findsOneWidget);
      }
      final groq = tester.getSemantics(
        find.bySemanticsLabel(TranscriptionSource.groq.label),
      );
      expect(groq, isSemantics(isSelected: true, isButton: true));
      final server = tester.getSemantics(
        find.bySemanticsLabel(TranscriptionSource.server.label),
      );
      expect(server, isSemantics(isSelected: false, isButton: true));
    });

    testWidgets('switching to OpenRouter without a key opens the key field', (
      tester,
    ) async {
      final account = HomeOrchestrator(tester);
      when(() => account.settings.setTranscriptionSource(any()))
          .thenAnswer((_) async {
            account.useOpenRouter();
            when(() => account.settings.hasCloudKey).thenReturn(false);
          });
      await account.pumpPanel(const AccountPanel());

      await tester.tap(find.text('OpenRouter'));
      await tester.pumpAndSettle();

      expect(
        verify(
          () => account.settings.setTranscriptionSource(
            TranscriptionSource.openRouter,
          ),
        ).callCount,
        1,
      );
      expect(find.byType(FieldPanel), findsOneWidget);
      expect(find.text('OpenRouter API key'), findsOneWidget);
    });

    testWidgets('switching to a source with a key just switches', (
      tester,
    ) async {
      final account = HomeOrchestrator(tester)..useServer();
      when(() => account.settings.setTranscriptionSource(any()))
          .thenAnswer((_) => Future.value());
      // Its key is already saved.
      when(() => account.settings.hasCloudKey).thenReturn(true);
      await account.pumpPanel(const AccountPanel());

      await tester.tap(find.text('Groq'));
      await tester.pumpAndSettle();

      expect(
        verify(
          () =>
              account.settings.setTranscriptionSource(TranscriptionSource.groq),
        ).callCount,
        1,
      );
      expect(find.byType(FieldPanel), findsNothing);
    });

    testWidgets('is locked while a dictation runs', (tester) async {
      final account = HomeOrchestrator(tester)..startRecording();
      await account.pumpPanel(const AccountPanel());

      await tester.tap(find.text('OpenRouter'));
      await tester.pumpAndSettle();

      verifyNever(() => account.settings.setTranscriptionSource(any()));
      expect(find.byType(FieldPanel), findsNothing);
      expect(
        find.byTooltip('Finish the recording first'),
        findsNWidgets(TranscriptionSource.values.length),
      );
    });
  });

  group('OpenRouter account', () {
    testWidgets('shows the model in use and that it keeps zero data', (
      tester,
    ) async {
      final account = HomeOrchestrator(tester)
        ..useOpenRouter(models: [mai], chosen: mai.id);
      await account.pumpPanel(const AccountPanel());

      expect(
        find.text('MAI-Transcribe 2 · zero data retention'),
        findsOneWidget,
      );
      expect(find.text('MAI-Transcribe 2'), findsOneWidget); // model row
      expect(find.text('Host'), findsNothing, reason: 'no host picker');
      final zdr = tester.widget<Switch>(find.byType(Switch));
      expect(zdr.value, isTrue);
      expect(find.text('Remove API key'), findsOneWidget);
    });

    testWidgets('a retired model is flagged in the identity and model row', (
      tester,
    ) async {
      final account = HomeOrchestrator(tester)
        ..useOpenRouter(
          models: [mai],
          chosen: 'acme/gone',
          problem: ModelSelectionProblem.retired,
        );
      await account.pumpPanel(const AccountPanel());

      expect(find.text('Your model was retired; choose another'), findsOne);
      expect(find.text('Retired'), findsOneWidget);
    });

    testWidgets('without a key, the model can’t be opened yet', (tester) async {
      final account = HomeOrchestrator(tester)..useOpenRouter();
      when(() => account.settings.cachedOpenRouterApiKey).thenReturn(null);
      when(() => account.settings.hasCloudKey).thenReturn(false);
      await account.pumpPanel(const AccountPanel());

      expect(find.text('Add your API key to start'), findsOneWidget);
      await tester.tap(find.text('Model'));
      await tester.pumpAndSettle();
      expect(find.byType(OpenRouterModelPanel), findsNothing);
    });

    testWidgets('with a key, the model row opens the picker', (tester) async {
      final account = HomeOrchestrator(tester)
        ..useOpenRouter(models: [mai], chosen: mai.id);
      await account.pumpPanel(const AccountPanel());

      await tester.tap(find.text('Model'));
      await tester.pumpAndSettle();

      expect(find.byType(OpenRouterModelPanel), findsOneWidget);
    });

    testWidgets('the language picked is OpenRouter’s, not Groq’s', (
      tester,
    ) async {
      const scrollStep = 200.0;
      final account = HomeOrchestrator(tester)
        ..useOpenRouter(models: [mai], chosen: mai.id);
      when(() => account.settings.setOpenRouterLanguage(any()))
          .thenAnswer((_) => Future.value());
      await account.pumpPanel(const AccountPanel());

      final french = find.text('French');
      await tester.ensureVisible(find.text('Language'));
      await tester.tap(find.text('Language'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(french, scrollStep);
      await tester.tap(french);
      await tester.pumpAndSettle();

      expect(
        verify(() => account.settings.setOpenRouterLanguage('fr')).callCount,
        1,
      );
      verifyNever(() => account.settings.setGroqLanguage(any()));
    });

    testWidgets('the rewrite model shows the default, or the one chosen', (
      tester,
    ) async {
      final account = HomeOrchestrator(tester)
        ..useOpenRouter(models: [mai], chosen: mai.id);
      await account.pumpPanel(const AccountPanel());
      expect(find.text('Rewrite model'), findsOneWidget);
      expect(find.text(AppConstants.openRouterTransformModelName), findsOne);

      when(() => account.settings.hasCustomRewriteModel).thenReturn(true);
      when(() => account.settings.openRouterRewriteModel)
          .thenReturn('deepseek/deepseek-v4.1-flash');
      account.settings.notifyListeners();
      await tester.pumpAndSettle();

      expect(find.text('deepseek-v4.1-flash'), findsOneWidget);
    });

    testWidgets(
      'a rewrite model is checked with OpenRouter before it is saved',
      (tester) async {
        final account = HomeOrchestrator(tester)
          ..useOpenRouter(models: [mai], chosen: mai.id);
        when(() => account.openRouterChat.checkModel('acme/slow'))
            .thenAnswer((_) async => 'This model always reasons first.');
        when(() => account.openRouterChat.checkModel('acme/fast'))
            .thenAnswer((_) async => null);
        when(() => account.settings.setOpenRouterRewriteModel(any()))
            .thenAnswer((_) => Future.value());
        await account.pumpPanel(const AccountPanel());

        await tester.tap(find.text('Rewrite model'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'acme/slow');
        await tester.tap(find.widgetWithText(AppButton, 'Save'));
        await tester.pumpAndSettle();
        expect(find.text('This model always reasons first.'), findsOneWidget);
        verifyNever(() => account.settings.setOpenRouterRewriteModel(any()));

        await tester.enterText(find.byType(TextField), 'acme/fast');
        await tester.tap(find.widgetWithText(AppButton, 'Save'));
        await tester.pumpAndSettle();

        expect(
          verify(() => account.settings.setOpenRouterRewriteModel('acme/fast'))
              .callCount,
          1,
        );
        expect(find.byType(FieldPanel), findsNothing);
      },
    );

    testWidgets('an empty rewrite model goes back to the default unchecked', (
      tester,
    ) async {
      final account = HomeOrchestrator(tester)
        ..useOpenRouter(models: [mai], chosen: mai.id);
      when(() => account.settings.hasCustomRewriteModel).thenReturn(true);
      when(() => account.settings.openRouterRewriteModel)
          .thenReturn('acme/fast');
      when(() => account.settings.setOpenRouterRewriteModel(any()))
          .thenAnswer((_) => Future.value());
      await account.pumpPanel(const AccountPanel());

      await tester.tap(find.text('Rewrite model'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.widgetWithText(AppButton, 'Save'));
      await tester.pumpAndSettle();

      verifyNever(() => account.openRouterChat.checkModel(any()));
      expect(
        verify(() => account.settings.setOpenRouterRewriteModel('')).callCount,
        1,
      );
    });

    testWidgets('turning zero data retention off asks first', (tester) async {
      final account = HomeOrchestrator(tester)
        ..useOpenRouter(models: [mai], chosen: mai.id);
      when(() => account.settings.setOpenRouterZdr(any()))
          .thenAnswer((_) => Future.value());
      await account.pumpPanel(const AccountPanel());

      await tester.tap(find.text('Zero data retention'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(AppButton, 'Cancel'));
      await tester.pumpAndSettle();
      verifyNever(() => account.settings.setOpenRouterZdr(any()));

      await tester.tap(find.text('Zero data retention'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(AppButton, 'Allow'));
      await tester.pumpAndSettle();
      expect(
        verify(() => account.settings.setOpenRouterZdr(false)).callCount,
        1,
      );
    });

    testWidgets('turning zero data retention back on needs no confirmation', (
      tester,
    ) async {
      final account = HomeOrchestrator(tester)
        ..useOpenRouter(models: [mai], chosen: mai.id);
      when(() => account.settings.openRouterZdr).thenReturn(false);
      when(() => account.settings.setOpenRouterZdr(any()))
          .thenAnswer((_) => Future.value());
      await account.pumpPanel(const AccountPanel());

      await tester.tap(find.text('Zero data retention'));
      await tester.pumpAndSettle();

      expect(
        verify(() => account.settings.setOpenRouterZdr(true)).callCount,
        1,
      );
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('Remove API key clears the OpenRouter key, not Groq’s', (
      tester,
    ) async {
      final account = HomeOrchestrator(tester)
        ..useOpenRouter(models: [mai], chosen: mai.id);
      when(() => account.settings.setOpenRouterApiKey(any()))
          .thenAnswer((_) => Future.value());
      await account.pumpPanel(const AccountPanel());

      await tester.tap(find.text('Remove API key'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('stops transcribing with OpenRouter'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(AppButton, 'Remove'));
      await tester.pumpAndSettle();

      expect(
        verify(() => account.settings.setOpenRouterApiKey('')).callCount,
        1,
      );
      verifyNever(() => account.settings.setGroqApiKey(any()));
    });

    testWidgets('credits the trademarks of the services it shows', (
      tester,
    ) async {
      final account = HomeOrchestrator(tester);
      await account.pumpPanel(const AccountPanel());

      expect(
        find.textContaining('trademarks of their respective owners'),
        findsOneWidget,
      );
    });
  });

  group('Model picker', () {
    testWidgets('most accurate first, by the WER snapshot, unmeasured last', (
      tester,
    ) async {
      final account = HomeOrchestrator(tester)
        // Listed by name, as the catalog gives them.
        ..useOpenRouter(models: [retiring, mai, unranked], chosen: mai.id);
      await account.pumpPanel(const OpenRouterModelPanel());

      double top(String text) => tester.getTopLeft(find.text(text)).dy;
      double middle(String text) => tester.getCenter(find.text(text)).dy;
      double right(String text) => tester.getTopRight(find.text(text)).dx;
      final rows = [mai.name, retiring.name, unranked.name].map(top).toList();
      expect(rows, orderedEquals([...rows]..sort()));
      // Each figure sits on its own model's row, right-aligned under WER.
      const sameRow = 12.0;
      expect(middle('2.0%'), closeTo(middle(mai.name), sameRow));
      expect(middle('2.4%'), closeTo(middle(retiring.name), sameRow));
      expect(middle('—'), closeTo(middle(unranked.name), sameRow));
      expect(right('2.0%'), right('WER'));
      expect(right('—'), right('WER'));
      expect(find.text('Model'), findsWidgets);
      expect(find.textContaining('WER is the word error rate'), findsOneWidget);
      expect(
        find.textContaining('Only models that can keep zero data'),
        findsOneWidget,
      );
    });

    testWidgets('the second line is maker • latency • retirement', (
      tester,
    ) async {
      final account = HomeOrchestrator(tester)
        ..useOpenRouter(models: [retiring, mai, unranked], chosen: mai.id);
      when(() => account.catalog.latencyOf(mai.id))
          .thenReturn(const Duration(milliseconds: 697));
      when(() => account.catalog.latencyOf(retiring.id))
          .thenReturn(const Duration(milliseconds: 1600));
      await account.pumpPanel(const OpenRouterModelPanel());

      expect(find.text('Microsoft AI • 700 ms'), findsOneWidget);
      expect(
        find.text('Microsoft AI • 1.6 s • retires 22 Dec'),
        findsOneWidget,
      );
      expect(find.text('Qwen'), findsOneWidget, reason: 'no latency yet');
    });

    testWidgets('opening it loads the list, then the latency', (tester) async {
      final account = HomeOrchestrator(tester)
        ..useOpenRouter(models: [mai], chosen: mai.id);
      await account.pumpPanel(const OpenRouterModelPanel());
      await tester.pump();

      verifyInOrder([
        () => account.catalog.refresh(),
        account.catalog.loadLatency,
      ]);
      expect(find.text(mai.name), findsOneWidget);
    });

    testWidgets('links to compare on OpenRouter and the accuracy board', (
      tester,
    ) async {
      final account = HomeOrchestrator(tester)
        ..useOpenRouter(models: [mai], chosen: mai.id);
      await account.pumpPanel(const OpenRouterModelPanel());

      expect(
        find.widgetWithText(AppLink, 'Compare on OpenRouter'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(AppLink, 'Accuracy leaderboard'),
        findsOneWidget,
      );
    });

    testWidgets('picking a model saves it and goes back', (tester) async {
      final account = HomeOrchestrator(tester)
        ..useOpenRouter(models: [mai, unranked], chosen: mai.id);
      when(() => account.settings.setOpenRouterModel(any()))
          .thenAnswer((_) => Future.value());
      await account.pumpPanel(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const OpenRouterModelPanel(),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(unranked.name));
      await tester.pumpAndSettle();

      expect(
        verify(() => account.settings.setOpenRouterModel(unranked.id))
            .callCount,
        1,
      );
      expect(find.byType(OpenRouterModelPanel), findsNothing);
    });

    testWidgets('a model that keeps data says so when ZDR is off', (
      tester,
    ) async {
      final account = HomeOrchestrator(tester)
        ..useOpenRouter(models: [grok], chosen: grok.id);
      when(() => account.settings.openRouterZdr).thenReturn(false);
      await account.pumpPanel(const OpenRouterModelPanel());

      expect(find.text('SpaceXSI • keeps data'), findsOneWidget);
      expect(find.text('2.3%'), findsOneWidget);
      expect(find.textContaining('Some of these models keep'), findsOneWidget);
    });

    testWidgets('a model hidden by zero data retention is explained', (
      tester,
    ) async {
      final account = HomeOrchestrator(tester)
        ..useOpenRouter(models: [mai, grok], chosen: grok.id);
      when(() => account.catalog.choices).thenReturn([mai]);
      await account.pumpPanel(const OpenRouterModelPanel());

      expect(
        find.textContaining('Your model, Grok STT 2.0, keeps data'),
        findsOneWidget,
      );
      expect(find.text(grok.name), findsNothing);
    });

    testWidgets('a vanished model is named, with a way to choose another', (
      tester,
    ) async {
      final account = HomeOrchestrator(tester)
        ..useOpenRouter(models: [mai], chosen: 'acme/gone');
      await account.pumpPanel(const OpenRouterModelPanel());

      expect(
        find.text('OpenRouter no longer serves acme/gone. Choose another.'),
        findsOneWidget,
      );
    });

    testWidgets('an empty list while loading, and why it failed after', (
      tester,
    ) async {
      final account = HomeOrchestrator(tester)..useOpenRouter();
      when(() => account.catalog.isRefreshing).thenReturn(true);
      await account.pumpPanel(const OpenRouterModelPanel());
      expect(find.text('[ loading models ]'), findsOneWidget);

      when(() => account.catalog.isRefreshing).thenReturn(false);
      when(() => account.catalog.lastError).thenReturn(
        const CloudError(
          service: 'OpenRouter',
          type: CloudErrorType.invalidApiKey,
          message: 'User not found.',
        ),
      );
      account.catalog.notifyListeners();
      await tester.pump();

      expect(find.text('[ couldn’t load models ]'), findsOneWidget);
      expect(find.text('Invalid OpenRouter API key. Check Account.'), findsOne);
    });

    testWidgets('Refresh forces a new list', (tester) async {
      final account = HomeOrchestrator(tester)
        ..useOpenRouter(models: [mai], chosen: mai.id);
      await account.pumpPanel(const OpenRouterModelPanel());

      await tester.tap(find.byTooltip('Refresh the list'));
      await tester.pump();

      expect(verify(() => account.catalog.refresh(force: true)).callCount, 1);
      // Then the figures, for any model new to the list: once on opening,
      // once after the refresh.
      const openAndRefresh = 2;
      expect(verify(account.catalog.loadLatency).callCount, openAndRefresh);
    });

    testWidgets('a figure still loading shows an ellipsis, not nothing', (
      tester,
    ) async {
      final account = HomeOrchestrator(tester)
        ..useOpenRouter(models: [mai], chosen: mai.id);
      when(() => account.catalog.isLoadingLatency).thenReturn(true);
      await account.pumpPanel(const OpenRouterModelPanel());

      expect(find.text('Microsoft AI • …'), findsOneWidget);
    });

    testWidgets('no model with zero data retention says so', (tester) async {
      final account = HomeOrchestrator(tester)..useOpenRouter();
      when(() => account.catalog.hasList).thenReturn(true);
      await account.pumpPanel(const OpenRouterModelPanel());

      expect(find.text('[ no models keep zero data ]'), findsOneWidget);
    });
  });

  group('Home prompt', () {
    testWidgets('“Choose” on a retired model opens the model picker', (
      tester,
    ) async {
      final home = HomeOrchestrator(tester)
        ..useOpenRouter(
          models: [mai],
          chosen: 'acme/gone',
          problem: ModelSelectionProblem.retired,
        );
      await home.pump();

      expect(find.text('[ model retired ]'), findsOneWidget);
      await tester.tap(find.text('Choose'));
      await tester.pumpAndSettle();

      expect(find.byType(OpenRouterModelPanel), findsOneWidget);
      expect(find.text(mai.name), findsOneWidget);
    });
  });
}
