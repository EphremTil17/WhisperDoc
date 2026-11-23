// Each tester.sendKeyEvent() is a separate key press the test makes on
// purpose (Tab, then Enter, then an arrow), so they can't share one value.
// ignore_for_file: avoid-late-keyword, prefer-match-file-name, prefer-moving-to-variable
import 'dart:ui';

import 'package:flutter/services.dart';

import 'package:flutter_client/infrastructure/theme/app_icons.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_client/controllers/recording_controller.dart';
import 'package:flutter_client/logic/models/custom_profile.dart';
import 'package:flutter_client/logic/models/dictation_profile.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/ui/screens/home/dialogs/profile_editor_dialog.dart';

import '../../../orchestrators/profile_action_button_orchestrator.dart';

class _MockSettingsService extends Mock
    with ChangeNotifier
    implements SettingsService {}

class _MockRecordingController extends Mock
    with ChangeNotifier
    implements RecordingController {}

void main() {
  setUpAll(() {
    registerFallbackValue(DictationProfile.raw);
  });

  late _MockSettingsService mockSettings;
  late _MockRecordingController mockController;

  setUp(() {
    mockSettings = _MockSettingsService();
    mockController = _MockRecordingController();

    when(() => mockSettings.dictationProfile).thenReturn(DictationProfile.raw);
    when(() => mockSettings.cachedGroqApiKey).thenReturn('gsk_test123');
    when(() => mockSettings.customProfiles).thenReturn([]);
    when(() => mockSettings.nextFreeCustomSlot()).thenReturn('custom1');
    when(() => mockSettings.setDictationProfile(any()))
        .thenAnswer((_) => Future<void>.value());

    when(() => mockController.isRecording).thenReturn(false);
    when(() => mockController.isTranscribing).thenReturn(false);
    when(() => mockController.isSessionActive).thenReturn(false);
  });

  ProfileActionButtonOrchestrator createOrchestrator(WidgetTester tester) =>
      ProfileActionButtonOrchestrator(
        tester: tester,
        mockSettings: mockSettings,
        mockController: mockController,
      );

  testWidgets('renders the picker glyph and the active style', (tester) async {
    when(() => mockSettings.dictationProfile)
        .thenReturn(DictationProfile.clean);

    final orchestrator = createOrchestrator(tester);
    await orchestrator.pumpButton();

    expect(find.text('Clean'), findsOneWidget);
    expect(find.byIcon(AppIcons.type), findsOneWidget);

    // Profile menu overlay should not be visible yet
    expect(find.text('Clean disfluencies'), findsNothing);
  });

  testWidgets(
    'tapping button opens vertical overlay menu with all 5 profiles',
    (tester) async {
      final orchestrator = createOrchestrator(tester);
      await orchestrator.openMenu();

      // All profile labels and descriptors in the vertical list are visible
      expect(find.text('Verbatim transcription'), findsOneWidget);
      expect(find.text('Clean disfluencies'), findsOneWidget);
      expect(find.text('Executive prose'), findsOneWidget);
      expect(find.text('Team chat style'), findsOneWidget);
      expect(find.text('Zero-omission spec'), findsOneWidget);
    },
  );

  testWidgets(
    'selecting a profile from the vertical list sets profile and closes menu',
    (tester) async {
      final orchestrator = createOrchestrator(tester);
      await orchestrator.openMenu();

      // Select 'Technical'
      await orchestrator.selectProfile('Zero-omission spec');

      verify(() => mockSettings.setDictationProfile(DictationProfile.technical))
          .called(1);

      // Menu should be closed
      expect(find.text('Zero-omission spec'), findsNothing);
    },
  );

  testWidgets('menu auto-closes when a recording session becomes active', (
    tester,
  ) async {
    final orchestrator = createOrchestrator(tester);
    await orchestrator.openMenu();
    final technicalProfileTile = find.text('Zero-omission spec');
    expect(technicalProfileTile, findsOneWidget);

    // Session starts
    when(() => mockController.isSessionActive).thenReturn(true);
    mockController.notifyListeners();
    await tester.pumpAndSettle();

    expect(technicalProfileTile, findsNothing);
  });

  testWidgets(
    'custom profiles render with pencil icon and built-in profiles do not',
    (tester) async {
      const custom = CustomProfile(
        storageKey: 'custom1',
        name: 'Custom Prompt',
        userPrompt: 'Rewrite prompt',
      );
      when(() => mockSettings.customProfiles).thenReturn([custom]);

      final orchestrator = createOrchestrator(tester);
      await orchestrator.openMenu();

      // Built-in profiles and custom profile are rendered
      expect(find.text('Custom Prompt'), findsOneWidget);
      expect(find.text('Verbatim transcription'), findsOneWidget);

      // Only the custom profile has the edit icon
      expect(find.byIcon(AppIcons.pencil), findsOneWidget);
    },
  );

  testWidgets(
    '+ Custom tile renders when free slot exists and is hidden when all slots are full',
    (tester) async {
      String? freeSlot = 'custom1';
      when(() => mockSettings.nextFreeCustomSlot()).thenAnswer((_) => freeSlot);

      final orchestrator = createOrchestrator(tester);
      await orchestrator.openMenu();

      final customProfileTile = find.text('Custom Profile');
      expect(customProfileTile, findsOneWidget);

      // Simulate 3 full slots
      freeSlot = null;
      mockSettings.notifyListeners();
      await tester.pumpAndSettle();

      expect(customProfileTile, findsNothing);
    },
  );

  testWidgets(
    'tapping pencil on custom profile tile opens ProfileEditorDialog in edit mode',
    (tester) async {
      const custom = CustomProfile(
        storageKey: 'custom1',
        name: 'Jira Format',
        userPrompt: 'Format for Jira tickets',
      );
      when(() => mockSettings.customProfiles).thenReturn([custom]);

      final orchestrator = createOrchestrator(tester);
      await orchestrator.openMenu();

      // Tap the edit icon
      await orchestrator.tapEditIcon();

      // ProfileEditorDialog should be visible
      expect(find.byType(ProfileEditorDialog), findsOneWidget);
      expect(find.text('Edit style'), findsOneWidget);
      expect(find.text('Jira Format'), findsOneWidget);
    },
  );

  testWidgets('button label displays custom profile name when active', (
    tester,
  ) async {
    const custom = CustomProfile(
      storageKey: 'custom1',
      name: 'Engineering Spec',
      userPrompt: 'Format as spec',
    );
    when(() => mockSettings.dictationProfile).thenReturn(custom);

    final orchestrator = createOrchestrator(tester);
    await orchestrator.pumpButton();

    expect(find.text('Engineering Spec'), findsOneWidget);
    expect(find.byIcon(AppIcons.type), findsOneWidget);
  });

  testWidgets('shows blocked state for LLM profile when Groq key is missing', (
    tester,
  ) async {
    when(() => mockSettings.cachedGroqApiKey).thenReturn(null);

    final orchestrator = createOrchestrator(tester);
    await orchestrator.openMenu();

    expect(find.text('Requires Groq API key'), findsWidgets);

    // Tap Pro
    await orchestrator.selectProfile('Pro');

    // Should NOT call setDictationProfile for blocked profile
    verifyNever(
      () => mockSettings.setDictationProfile(DictationProfile.professional),
    );
    expect(find.byIcon(AppIcons.keyRound), findsWidgets);
  });

  testWidgets(
    'switching to Raw after other profiles does not throw any assertion',
    (tester) async {
      when(() => mockSettings.dictationProfile)
          .thenReturn(DictationProfile.professional);

      final orchestrator = createOrchestrator(tester);
      await orchestrator.openMenu(buttonLabel: 'Pro');

      // Select Raw
      final verbatimTile = find.text('Verbatim transcription');
      await tester.tap(verbatimTile);
      await tester.pumpAndSettle();

      verify(() => mockSettings.setDictationProfile(DictationProfile.raw))
          .called(1);
      expect(verbatimTile, findsNothing);
    },
  );

  testWidgets(
    'hovering displays tooltip above the button and does not open menu',
    (tester) async {
      tester.view.physicalSize = const Size(420, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final orchestrator = createOrchestrator(tester);
      await orchestrator.pumpButton();

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);

      await gesture.moveTo(tester.getCenter(find.text('Raw').first));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final tooltipTextFinder = find.textContaining('Profile: Raw');
      expect(find.byType(Tooltip), findsWidgets);
      expect(tooltipTextFinder, findsOneWidget);
      final tooltipRect = tester.getRect(tooltipTextFinder);
      final buttonRect = tester.getRect(find.byType(AnimatedContainer).first);

      // The picker sits on the bottom bar, so its tooltip opens above it.
      expect(tooltipRect.bottom, lessThanOrEqualTo(buttonRect.top));

      // Verify vertical menu list is NOT opened on hover (click-only model)
      expect(find.text('Verbatim transcription'), findsNothing);
    },
  );

  testWidgets('tapping outside the menu dismisses the overlay', (tester) async {
    final orchestrator = createOrchestrator(tester);
    await orchestrator.openMenu();
    final verbatimTile = find.text('Verbatim transcription');
    expect(verbatimTile, findsOneWidget);

    // Tap outside (e.g. top-left corner of screen)
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // Menu should be closed
    expect(verbatimTile, findsNothing);
  });

  group('keyboard and screen readers', () {
    testWidgets('Tab, Enter, an arrow and Enter pick a style', (tester) async {
      final orchestrator = createOrchestrator(tester);
      await orchestrator.pumpButton();

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Verbatim transcription'), findsOneWidget);

      // The menu opens on the current style (Raw); the next one is Clean.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      final picked = verify(
        () => mockSettings.setDictationProfile(DictationProfile.clean),
      );
      expect(picked.callCount, 1);
      expect(find.text('Verbatim transcription'), findsNothing);
    });

    testWidgets('Tab reaches the add-style row and Enter opens the editor', (
      tester,
    ) async {
      final orchestrator = createOrchestrator(tester);
      await orchestrator.openMenu();

      // From the current style (Raw) past the other four to the last row.
      const stylesAfterRaw = 4;
      for (var i = 0; i <= stylesAfterRaw; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.byType(ProfileEditorDialog), findsOneWidget);
      expect(find.text('Verbatim transcription'), findsNothing);
    });

    testWidgets('hovering the add-style row fills it with the band', (
      tester,
    ) async {
      // Hover highlights show only in desktop (traditional) focus mode, which
      // the app runs in on Windows; tests otherwise start in touch mode.
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );
      final orchestrator = createOrchestrator(tester);
      await orchestrator.openMenu();
      BoxDecoration? addRowFill() =>
          tester
                  .widget<AnimatedContainer>(
                    find
                        .ancestor(
                          of: find.text('Custom Profile'),
                          matching: find.byType(AnimatedContainer),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration?;
      expect(addRowFill()?.color, Colors.transparent);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('Custom Profile')));
      await tester.pumpAndSettle();

      expect(addRowFill()?.color, AppColors.band);
    });

    testWidgets('Esc closes the menu and returns focus to the button', (
      tester,
    ) async {
      final orchestrator = createOrchestrator(tester);
      await orchestrator.openMenu();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.text('Verbatim transcription'), findsNothing);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Output style');
    });

    testWidgets('the button, styles and edit action are labelled', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      when(() => mockSettings.customProfiles).thenReturn([
        const CustomProfile(
          storageKey: 'custom1',
          name: 'Standup',
          userPrompt: 'Summarise as standup notes.',
        ),
      ]);
      final orchestrator = createOrchestrator(tester);
      await orchestrator.openMenu();

      expect(find.bySemanticsLabel('Output style, Raw'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'^Raw, Verbatim transcription')),
        findsOneWidget,
      );
      expect(find.byTooltip('Edit Standup'), findsOneWidget);
      semantics.dispose();
    });
  });
}
