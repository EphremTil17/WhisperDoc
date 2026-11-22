import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/ui/shared/widgets/press_nudge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  const label = Key('label');

  Future<double> pumpNudge(WidgetTester tester, {bool enabled = true}) async {
    await tester.pumpWidget(
      Center(
        child: PressNudge(
          enabled: enabled,
          child: const SizedBox(key: label, width: 80, height: 40),
        ),
      ),
    );

    return tester.getTopLeft(find.byKey(label)).dy;
  }

  double top(WidgetTester tester) => tester.getTopLeft(find.byKey(label)).dy;

  group('PressNudge', () {
    testWidgets('drops on pointer down and climbs back a pixel per step', (
      tester,
    ) async {
      final rest = await pumpNudge(tester);
      final press = await tester.startGesture(
        tester.getCenter(find.byKey(label)),
      );
      await tester.pump();
      expect(top(tester), rest + AppSizes.pressDepth);

      await press.up();
      await tester.pump();
      expect(top(tester), rest + AppSizes.pressDepth, reason: 'held a step');

      await tester.pump(AppMotion.pressStep);
      expect(top(tester), rest + AppSizes.pressDepth - 1);

      await tester.pump(AppMotion.pressStep);
      expect(top(tester), rest);
    });

    testWidgets('a disabled control does not move', (tester) async {
      final rest = await pumpNudge(tester, enabled: false);
      final press = await tester.startGesture(
        tester.getCenter(find.byKey(label)),
      );
      await tester.pump();
      expect(top(tester), rest);
      await press.up();
    });

    testWidgets('re-pressing mid-climb resets cleanly to full depth', (
      tester,
    ) async {
      final rest = await pumpNudge(tester);
      final center = tester.getCenter(find.byKey(label));

      final first = await tester.startGesture(center);
      await tester.pump();
      await first.up();
      await tester.pump(AppMotion.pressStep);
      expect(top(tester), rest + AppSizes.pressDepth - 1);

      final second = await tester.startGesture(center);
      await tester.pump();
      expect(top(tester), rest + AppSizes.pressDepth);

      await second.up();
      await tester.pump(AppMotion.pressStep);
      await tester.pump(AppMotion.pressStep);
      expect(top(tester), rest);
    });

    testWidgets('overlapping pointer lifts never push depth negative', (
      tester,
    ) async {
      final rest = await pumpNudge(tester);
      final center = tester.getCenter(find.byKey(label));

      final first = await tester.startGesture(center);
      final second = await tester.startGesture(center);
      await tester.pump();

      await first.up();
      await second.cancel();
      await tester.pump(AppMotion.pressStep);
      await tester.pump(AppMotion.pressStep);
      await tester.pump(AppMotion.pressStep);
      expect(top(tester), rest);
    });

    testWidgets('disposing mid-climb leaves no pending timers', (tester) async {
      await pumpNudge(tester);
      final press = await tester.startGesture(
        tester.getCenter(find.byKey(label)),
      );
      await tester.pump();
      await press.up();
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(AppMotion.pressStep);
      expect(find.byType(PressNudge), findsNothing);
    });
  });
}
