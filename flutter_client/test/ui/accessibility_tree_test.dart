// Each pump advances past a different hover or tap, so the repeats have no
// shared value to hold; the mocks notify as the real services would.
// ignore_for_file: prefer-moving-to-variable, no-magic-number, invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
import 'package:flutter/gestures.dart';
import 'package:flutter_client/logic/models/speech_model.dart';
import 'package:flutter_client/logic/models/transcription_source.dart';
import 'package:flutter_client/ui/screens/account/open_router_model_panel.dart';
import 'package:flutter_client/ui/screens/account/widgets/source_segment.dart';
import 'package:flutter_client/ui/screens/account_panel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../fakes/accessibility_tree_binding.dart';
import '../orchestrators/home_orchestrator.dart';

/// Every update the framework sends must be one the Windows engine accepts;
/// otherwise it logs "Failed to update ui::AXTree … will not be in the tree"
/// and screen readers keep a stale tree from then on.
void main() {
  final binding = AccessibilityTreeBinding();
  const hoverFor = Duration(seconds: 2);

  setUpAll(() => registerFallbackValue(TranscriptionSource.server));
  setUp(binding.tree.rejections.clear);

  Future<TestGesture> mouse(WidgetTester tester) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    return gesture;
  }

  Future<void> hover(WidgetTester tester, TestGesture mouse, Finder at) async {
    await mouse.moveTo(tester.getCenter(at));
    await tester.pump(hoverFor);
  }

  testWidgets('switching source in Account, a segment’s tooltip showing', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final account = HomeOrchestrator(tester);
    when(() => account.settings.setTranscriptionSource(any()))
        .thenAnswer((call) async {
          final source = call.positionalArguments.first as TranscriptionSource;
          when(() => account.settings.transcriptionSource).thenReturn(source);
          account.settings.notifyListeners();
        });
    await account.pumpPanel(const AccountPanel());
    final pointer = await mouse(tester);

    for (final label in ['OpenRouter', 'Self-hosted', 'Groq', 'OpenRouter']) {
      final segment = find.byWidgetPredicate(
        (w) => w is SourceSegment && w.label == label,
      );
      await hover(tester, pointer, segment);
      await pointer.down(tester.getCenter(segment));
      await pointer.up();
      await tester.pump(hoverFor);
    }

    expect(binding.tree.rejections, isEmpty);
    handle.dispose();
  });

  testWidgets('a dictation on the home screen, with every tooltip shown', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final home = HomeOrchestrator(tester);
    await home.pump();
    final pointer = await mouse(tester);

    home
      ..startRecording()
      ..showTranscript('word ' * 200);
    home.recording.notifyListeners();
    await tester.pump();
    await hover(
      tester,
      pointer,
      find.byTooltip('Other controls are locked while recording'),
    );
    when(() => home.recording.isRecording).thenReturn(false);
    when(() => home.recording.isSessionActive).thenReturn(false);
    home.showTranscript('word ' * 200, age: const Duration(minutes: 2));
    home.recording.notifyListeners();
    await tester.pump(hoverFor);
    for (final tip in [
      'Minimize',
      'Close',
      'History',
      'Settings',
      'Copy again',
    ]) {
      await hover(tester, pointer, find.byTooltip(tip).first);
    }
    await hover(tester, pointer, find.text('Raw'));

    expect(binding.tree.rejections, isEmpty);
    handle.dispose();
  });

  testWidgets('the model picker, with its tooltips shown', (tester) async {
    final handle = tester.ensureSemantics();
    final account = HomeOrchestrator(tester)
      ..useOpenRouter(
        models: const [
          SpeechModel(
            id: 'microsoft/mai-transcribe-2',
            fullName: 'Microsoft AI: MAI-Transcribe 2',
            zdr: true,
          ),
        ],
        chosen: 'microsoft/mai-transcribe-2',
      );
    await account.pumpPanel(const OpenRouterModelPanel());
    final pointer = await mouse(tester);

    await hover(tester, pointer, find.byTooltip('Refresh the list'));
    await hover(tester, pointer, find.text('WER'));
    await hover(tester, pointer, find.byTooltip('Back'));

    expect(binding.tree.rejections, isEmpty);
    handle.dispose();
  });
}
