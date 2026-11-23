// The shader program is loaded once, in setUpAll, off the fake clock; the
// only class here is the private stage the background is shown on.
// ignore_for_file: avoid-late-keyword, prefer-match-file-name
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_client/ui/shared/widgets/topography_background.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  /// The wait the driver leaves between drift-only frames.
  const driftGap = Duration(milliseconds: 12);
  const longWait = Duration(seconds: 1);
  const cursor = Offset(200, 150);

  /// Real time between frames while the relief falls, and how many such
  /// frames it may take before the test gives up.
  const realFrame = Duration(milliseconds: 120);
  const maxFallFrames = 10;

  late ui.FragmentProgram program;

  setUpAll(() async {
    program = await ui.FragmentProgram.fromAsset('shaders/topography.frag');
  });

  Finder within(Type type) => find.descendant(
    of: find.byType(TopographyBackground),
    matching: find.byType(type),
  );

  /// Repaints of the contour layer so far, one per frame the driver ran.
  int frames(WidgetTester tester) {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      within(RepaintBoundary),
    );

    return boundary.debugSymmetricPaintCount +
        boundary.debugAsymmetricPaintCount;
  }

  /// The driver's ticker has asked for the next vsync.
  bool ticking(WidgetTester tester) =>
      tester.binding.transientCallbackCount > 0;

  /// Shows a full relief that only drifts: a still map has no rise to play,
  /// so turning motion on afterwards leaves nothing but the drift.
  Future<void> showDrift(WidgetTester tester) async {
    await tester.pumpWidget(_Stage(program: program, moving: false));
    await tester.pump();
    await tester.pumpWidget(_Stage(program: program));
    // The drift frame the change asked for; it hands over to the timer.
    await tester.pump();
  }

  group('TopographyBackground driver', () {
    testWidgets('without a shader program it shows only the child', (
      tester,
    ) async {
      await tester.pumpWidget(_Stage(program: program, noProgram: true));
      await tester.pump();
      await tester.tapAt(cursor);

      expect(find.byKey(_Stage.childKey), findsOneWidget);
      expect(within(CustomPaint), findsNothing);
      expect(ticking(tester), isFalse);
    });

    testWidgets('rises from flat ground at the display rate', (tester) async {
      await tester.pumpWidget(_Stage(program: program));
      await tester.pump();
      final before = frames(tester);

      await tester.pump();

      expect(frames(tester), before + 1);
      // Already waiting on the next vsync, with no timer in between.
      expect(ticking(tester), isTrue);
    });

    testWidgets('paces the drift alone with a timer, not every vsync', (
      tester,
    ) async {
      await showDrift(tester);
      final before = frames(tester);
      expect(ticking(tester), isFalse);

      await tester.pump(driftGap - const Duration(milliseconds: 1));
      expect(frames(tester), before);

      await tester.pump(const Duration(milliseconds: 1));
      final drifted = frames(tester);
      expect(drifted, before + 1);
      expect(ticking(tester), isFalse);

      await tester.pump(driftGap);
      expect(frames(tester), drifted + 1);
    });

    testWidgets('the cursor brings a frame every vsync', (tester) async {
      await showDrift(tester);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);

      await mouse.moveTo(cursor);
      expect(ticking(tester), isTrue);
      await tester.pump();
      await tester.pump();

      expect(ticking(tester), isTrue);
    });

    testWidgets('a click brings a frame every vsync', (tester) async {
      await showDrift(tester);

      await tester.tapAt(cursor);
      await tester.pump();

      expect(ticking(tester), isTrue);
    });

    for (final reduceMotion in [false, true]) {
      final why = reduceMotion ? 'reduced motion' : 'motion off';
      testWidgets('with $why the map is drawn once and ignores input', (
        tester,
      ) async {
        await tester.pumpWidget(
          _Stage(
            program: program,
            moving: reduceMotion,
            reduceMotion: reduceMotion,
          ),
        );
        await tester.pump();
        expect(within(CustomPaint), findsOneWidget);
        final drawn = frames(tester);

        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        await mouse.moveTo(cursor);
        await tester.tapAt(cursor);
        await tester.pump(longWait);

        expect(ticking(tester), isFalse);
        expect(frames(tester), drawn);
      });
    }

    testWidgets('a muted ticker runs nothing until it is unmuted', (
      tester,
    ) async {
      await tester.pumpWidget(_Stage(program: program, tickerEnabled: false));
      await tester.pump();
      final drawn = frames(tester);

      await tester.pump(longWait);
      expect(ticking(tester), isFalse);
      expect(frames(tester), drawn);

      await tester.pumpWidget(_Stage(program: program));
      expect(ticking(tester), isTrue);
    });

    testWidgets('losing focus stops frames and finishes the rise', (
      tester,
    ) async {
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      await tester.pumpWidget(_Stage(program: program));
      await tester.pump();
      expect(ticking(tester), isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      expect(ticking(tester), isFalse);
      // The settled map is drawn once, then nothing runs.
      await tester.pump();
      final settled = frames(tester);
      await tester.pump(longWait);
      expect(frames(tester), settled);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(ticking(tester), isTrue);
      await tester.pump();
      // Risen while away: only the drift is left, paced by the timer.
      expect(ticking(tester), isFalse);
      final resumed = frames(tester);
      await tester.pump(driftGap);
      expect(frames(tester), resumed + 1);
    });

    testWidgets('going inactive flattens the relief, then stops', (
      tester,
    ) async {
      await showDrift(tester);
      final contours = tester.renderObject(within(CustomPaint));
      expect(contours, paints..rect());

      await tester.pumpWidget(_Stage(program: program, active: false));
      await tester.pump();
      expect(ticking(tester), isTrue);

      // The fall runs on the real clock (a quarter second), each frame
      // advancing it by at most a tenth of a second.
      for (var frame = 0; frame < maxFallFrames && ticking(tester); frame++) {
        await tester.runAsync(() => Future<void>.delayed(realFrame));
        await tester.pump();
      }

      expect(ticking(tester), isFalse);
      expect(contours, paintsNothing);
      final flat = frames(tester);
      await tester.pump(longWait);
      expect(frames(tester), flat);
    });

    testWidgets('disposing cancels the waiting drift frame', (tester) async {
      await showDrift(tester);

      await tester.pumpWidget(const SizedBox.shrink());

      // A drift timer left behind would fail this test: flutter_test rejects
      // timers still pending once the tree is gone.
      expect(find.byType(TopographyBackground), findsNothing);
      expect(ticking(tester), isFalse);
    });
  });
}

/// The background as the app shows it, with a test program or none.
class _Stage extends StatelessWidget {
  static const childKey = Key('child');

  final ui.FragmentProgram program;
  final bool noProgram;
  final bool active;
  final bool moving;
  final bool reduceMotion;
  final bool tickerEnabled;

  const _Stage({
    required this.program,
    this.noProgram = false,
    this.active = true,
    this.moving = true,
    this.reduceMotion = false,
    this.tickerEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: TickerMode(
          enabled: tickerEnabled,
          child: TopographyBackground(
            active: active,
            moving: moving,
            program: Future.value(noProgram ? null : program),
            child: const SizedBox.expand(key: childKey),
          ),
        ),
      ),
    );
  }
}
