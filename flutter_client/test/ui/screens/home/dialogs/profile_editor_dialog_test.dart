// ignore_for_file: avoid-late-keyword, prefer-match-file-name
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_client/logic/models/custom_profile.dart';
import 'package:flutter_client/logic/models/dictation_profile.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/ui/screens/home/dialogs/profile_editor_dialog.dart';
import '../../../../orchestrators/profile_editor_dialog_orchestrator.dart';

class _MockSettingsService extends Mock
    with ChangeNotifier
    implements SettingsService {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      const CustomProfile(
        storageKey: 'custom1',
        name: 'Fallback',
        userPrompt: 'Fallback prompt',
      ),
    );
    registerFallbackValue(DictationProfile.raw);
  });

  late _MockSettingsService mockSettings;

  setUp(() {
    mockSettings = _MockSettingsService();
    when(
      () => mockSettings.saveCustomProfile(any()),
    ).thenAnswer((_) => Future<void>.value());
    when(
      () => mockSettings.setDictationProfile(any()),
    ).thenAnswer((_) => Future<void>.value());
    when(
      () => mockSettings.deleteCustomProfile(any()),
    ).thenAnswer((_) => Future<void>.value());
  });

  ProfileEditorDialogOrchestrator createOrchestrator(WidgetTester tester) =>
      ProfileEditorDialogOrchestrator(
        tester: tester,
        mockSettings: mockSettings,
      );

  group('ProfileEditorDialog - Create Mode', () {
    testWidgets(
      'renders title, default name, empty prompt, and disabled Save',
      (tester) async {
        final orchestrator = createOrchestrator(tester);
        await orchestrator.pumpDialog(slotKey: 'custom1');

        expect(find.text('New Custom Profile'), findsOneWidget);
        expect(find.text('Custom 1'), findsOneWidget);
        expect(find.text('Delete'), findsNothing);

        // Save button is disabled because prompt is empty
        final saveButton = tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Save'),
        );
        expect(saveButton.onPressed, isNull);
      },
    );

    testWidgets(
      'entering valid prompt enables Save button and counter updates',
      (tester) async {
        final orchestrator = createOrchestrator(tester);
        await orchestrator.pumpDialog(slotKey: 'custom1');

        // Find the prompt TextField (maxLines: 6)
        const expectedFieldCount = 2;
        final textFields = find.byType(TextField);
        expect(textFields, findsNWidgets(expectedFieldCount));

        await orchestrator.enterPrompt('Rewrite into concise bullets');

        expect(find.textContaining('28 / 2000 chars'), findsOneWidget);

        final saveButton = tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Save'),
        );
        expect(saveButton.onPressed, isNotNull);
      },
    );

    testWidgets('tapping Save saves profile and activates it', (tester) async {
      final orchestrator = createOrchestrator(tester);
      await orchestrator.pumpDialog(slotKey: 'custom1');

      await orchestrator.enterName('Jira Spec');
      await orchestrator.enterPrompt('Format as Jira user story');
      await orchestrator.tapSave();

      const expected = CustomProfile(
        storageKey: 'custom1',
        name: 'Jira Spec',
        userPrompt: 'Format as Jira user story',
      );

      verify(() => mockSettings.saveCustomProfile(expected)).called(1);
      verify(() => mockSettings.setDictationProfile(expected)).called(1);
      expect(find.byType(ProfileEditorDialog), findsNothing);
    });

    testWidgets('tapping Cancel dismisses dialog without persisting anything', (
      tester,
    ) async {
      final orchestrator = createOrchestrator(tester);
      await orchestrator.openViaShowDialog(slotKey: 'custom1');

      final dialogTitle = find.text('New Custom Profile');
      expect(dialogTitle, findsOneWidget);

      await orchestrator.tapCancel();

      expect(dialogTitle, findsNothing);
      verifyNever(() => mockSettings.saveCustomProfile(any()));
    });
  });

  group('ProfileEditorDialog - Edit Mode', () {
    const existingProfile = CustomProfile(
      storageKey: 'custom2',
      name: 'Existing Name',
      userPrompt: 'Existing Prompt Content',
    );

    testWidgets(
      'renders Edit title, existing values, Delete button, and enabled Save',
      (tester) async {
        final orchestrator = createOrchestrator(tester);
        await orchestrator.pumpDialog(
          slotKey: 'custom2',
          existing: existingProfile,
        );

        expect(find.text('Edit Custom Profile'), findsOneWidget);
        expect(find.text('Existing Name'), findsOneWidget);
        expect(find.text('Existing Prompt Content'), findsOneWidget);
        expect(find.text('Delete'), findsOneWidget);

        final saveButton = tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Save'),
        );
        expect(saveButton.onPressed, isNotNull);
      },
    );

    testWidgets('tapping Delete calls deleteCustomProfile with slotKey', (
      tester,
    ) async {
      final orchestrator = createOrchestrator(tester);
      await orchestrator.pumpDialog(
        slotKey: 'custom2',
        existing: existingProfile,
      );

      await orchestrator.tapDelete();

      verify(() => mockSettings.deleteCustomProfile('custom2')).called(1);
      expect(find.byType(ProfileEditorDialog), findsNothing);
    });

    testWidgets('clearing prompt disables and grays out Save button', (
      tester,
    ) async {
      final orchestrator = createOrchestrator(tester);
      await orchestrator.pumpDialog(
        slotKey: 'custom2',
        existing: existingProfile,
      );

      await orchestrator.enterPrompt('   ');

      final saveButtonFinder = find.widgetWithText(ElevatedButton, 'Save');
      final saveButton = tester.widget<ElevatedButton>(saveButtonFinder);
      expect(saveButton.onPressed, isNull);

      final saveText = tester.widget<Text>(
        find.descendant(of: saveButtonFinder, matching: find.byType(Text)),
      );
      expect(saveText.style?.color, Colors.white38);
    });

    testWidgets('clearing name disables and grays out Save button', (
      tester,
    ) async {
      final orchestrator = createOrchestrator(tester);
      await orchestrator.pumpDialog(
        slotKey: 'custom2',
        existing: existingProfile,
      );

      await orchestrator.enterName('   ');

      final saveButtonFinder = find.widgetWithText(ElevatedButton, 'Save');
      final saveButton = tester.widget<ElevatedButton>(saveButtonFinder);
      expect(saveButton.onPressed, isNull);

      final saveText = tester.widget<Text>(
        find.descendant(of: saveButtonFinder, matching: find.byType(Text)),
      );
      expect(saveText.style?.color, Colors.white38);
    });
  });
}
