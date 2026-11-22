import 'package:flutter_client/ui/shared/widgets/topography_background.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('TopographyBackground driver', () {
    testWidgets('stops scheduling frames when unfocused or still and disposes cleanly', (
      tester,
    ) async {
      /// Shows the background as [active] and [moving], lets one frame
      /// through, and reports whether it asked for another.
      Future<bool> asksForFrames({
        required bool active,
        required bool moving,
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            home: TopographyBackground(
              active: active,
              moving: moving,
              child: const SizedBox.expand(),
            ),
          ),
        );
        await tester.pump();

        return tester.binding.hasScheduledFrame;
      }

      expect(await asksForFrames(active: true, moving: false), isFalse);

      // Flipping to moving=true then inactive lifecycle must stop frames cleanly.
      await asksForFrames(active: true, moving: true);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      // Flattening via active=false while still disposes without pending timers.
      expect(await asksForFrames(active: false, moving: false), isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(find.byType(TopographyBackground), findsNothing);
    });
  });
}
