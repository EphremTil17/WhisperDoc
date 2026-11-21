import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_client/infrastructure/theme/app_icons.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_client/ui/shared/widgets/app_button.dart';
import 'package:flutter_client/ui/shared/widgets/caption_band.dart';
import 'package:flutter_client/ui/shared/widgets/pixel_meter.dart';

import '../../../orchestrators/home_orchestrator.dart';

void main() {
  const transcript = 'Quick update on the release.';

  AppButton recordButton(WidgetTester tester) =>
      tester.widget<AppButton>(find.byType(AppButton).last);

  group('Home screen', () {
    testWidgets('ready: cue, shortcut and an enabled Record', (tester) async {
      final home = HomeOrchestrator(tester);
      await home.pump();

      expect(find.text('[ ready ]'), findsOneWidget);
      expect(find.text('Ctrl Q'), findsOneWidget);
      expect(find.text('to talk'), findsOneWidget);
      expect(recordButton(tester).onPressed, isNotNull);
      expect(find.byTooltip('History'), findsOneWidget);
      expect(find.byTooltip('Settings'), findsOneWidget);
    });

    testWidgets('Record toggles recording', (tester) async {
      final home = HomeOrchestrator(tester);
      await home.pump();

      await tester.tap(find.text('Record'));
      verify(home.recording.toggleRecording).called(1);
    });

    testWidgets('the last transcript is set as captions', (tester) async {
      final home = HomeOrchestrator(tester)..showTranscript(transcript);
      await home.pump();

      expect(find.byType(CaptionBand), findsOneWidget);
      expect(find.bySemanticsLabel(transcript), findsOneWidget);
      expect(find.text('just now'), findsOneWidget);
      expect(find.byTooltip('Copy again'), findsOneWidget);
    });

    testWidgets('listening: Stop, the meter, and locked controls', (tester) async {
      final home = HomeOrchestrator(tester)..startRecording();
      await home.pump();

      expect(find.text('Stop'), findsOneWidget);
      expect(find.byType(PixelMeter), findsOneWidget);
      expect(find.text('to stop'), findsOneWidget);
      expect(find.byIcon(AppIcons.lock), findsOneWidget);
      expect(find.byTooltip('History'), findsNothing);
    });

    testWidgets('no Groq key: one fix, Record disabled, crimson badge', (tester) async {
      final home = HomeOrchestrator(tester)..removeGroqKey();
      await home.pump();

      expect(find.text('[ not set up ]'), findsOneWidget);
      expect(find.text('Add key'), findsOneWidget);
      expect(recordButton(tester).onPressed, isNull);
      expect(find.byTooltip('Account · needs attention'), findsOneWidget);
    });

    testWidgets('no microphone wins and points at settings', (tester) async {
      final home = HomeOrchestrator(tester)..unplugMicrophone();
      await home.pump();

      expect(find.text('[ no microphone ]'), findsOneWidget);
      expect(find.text('Choose'), findsOneWidget);
    });

    testWidgets('an optional update only adds the amber badge', (tester) async {
      final home = HomeOrchestrator(tester)..offerUpdate();
      await home.pump();

      expect(find.text('[ ready ]'), findsOneWidget);
      expect(find.byTooltip('Account · update available'), findsOneWidget);
    });
  });
}
