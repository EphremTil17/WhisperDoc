import 'package:flutter_client/infrastructure/theme/app_icons.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/services/utility/logging_service.dart';
import 'package:flutter_client/ui/screens/logs_panel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../orchestrators/home_orchestrator.dart';

void main() {
  final logging = LoggingService();

  Color? colorOf(String message) =>
      (find.text(message).evaluate().single.widget as Text).style?.color;

  ScrollPosition logScroll(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ),
      )
      .position;

  group('LogsPanel', () {
    // The log is an app-wide singleton, so this runs before anything logs.
    testWidgets('an empty log says so and has nothing to copy', (tester) async {
      await HomeOrchestrator(tester).pumpPanel(const LogsPanel());

      expect(find.text('Logs'), findsOneWidget);
      expect(find.text('[ no logs yet ]'), findsOneWidget);
      final copyAll = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, AppIcons.copy),
      );
      expect(copyAll.onPressed, isNull);
    });

    testWidgets('shows each line with its time and level', (tester) async {
      logging.info('Connected to server');
      logging.error('Upload failed', error: 'timeout');
      final latest = logging.logs.last;
      await HomeOrchestrator(tester).pumpPanel(const LogsPanel());

      expect(find.text('Connected to server'), findsOneWidget);
      expect(find.text('Upload failed - timeout'), findsOneWidget);
      expect(find.text('${latest.time}  ERROR'), findsOneWidget);
      expect(find.text('[ no logs yet ]'), findsNothing);
      final copyAll = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, AppIcons.copy),
      );
      expect(copyAll.onPressed, isNotNull);
    });

    testWidgets('errors read in alert, warnings in white, the rest muted', (
      tester,
    ) async {
      logging.error('Disk full');
      logging.warning('Microphone unplugged');
      logging.debug('Frame sent');
      await HomeOrchestrator(tester).pumpPanel(const LogsPanel());

      expect(colorOf('Disk full'), AppColors.alert);
      expect(colorOf('Microphone unplugged'), AppColors.text);
      expect(colorOf('Frame sent'), AppColors.textMuted);
    });

    testWidgets('new lines appear while the panel is open', (tester) async {
      await HomeOrchestrator(tester).pumpPanel(const LogsPanel());

      logging.warning('Reconnecting in 5s');
      await tester.pump();
      await tester.pump();

      expect(find.text('Reconnecting in 5s'), findsOneWidget);
    });

    testWidgets('follows new lines while scrolled to the end', (tester) async {
      const lines = 80;
      for (var i = 0; i < lines; i++) {
        logging.info('Follow line $i');
      }
      await HomeOrchestrator(tester).pumpPanel(const LogsPanel());
      await tester.pump();
      expect(find.text('Follow line ${lines - 1}'), findsOneWidget);

      logging.info('Newest line');
      await tester.pump();
      await tester.pump();

      final position = logScroll(tester);
      expect(find.text('Newest line'), findsOneWidget);
      expect(position.pixels, position.maxScrollExtent);
    });

    testWidgets('does not pull the reader back down after scrolling up', (
      tester,
    ) async {
      const lines = 80;
      for (var i = 0; i < lines; i++) {
        logging.info('Reading line $i');
      }
      await HomeOrchestrator(tester).pumpPanel(const LogsPanel());
      await tester.pump();
      logScroll(tester).jumpTo(0);
      await tester.pump();

      logging.info('Arrived while reading');
      await tester.pump();
      await tester.pump();

      expect(logScroll(tester).pixels, 0);
      expect(find.text('Arrived while reading'), findsNothing);
    });
  });
}
