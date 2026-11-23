// ignore_for_file: prefer-match-file-name
import 'package:flutter_client/services/utility/automation_service.dart';
import 'package:flutter_client/services/utility/logging_service.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockSettingsService extends Mock implements SettingsService {}

void main() {
  group('AutomationService logging hygiene', () {
    test(
      'never logs transcript plaintext in normal or incognito mode',
      () async {
        const secretTranscript = 'my-private-medical-note-98765';
        const minExpectedEntries = 2;
        final logger = LoggingService();
        final settings = _MockSettingsService();
        when(() => settings.autoCopy).thenReturn(false);
        when(() => settings.autoPaste).thenReturn(false);

        final automation = AutomationService(settings);
        final beforeCount = logger.logs.length;
        for (final incognito in [false, true]) {
          when(() => settings.incognitoMode).thenReturn(incognito);
          await automation.runAutomation(secretTranscript);
        }

        final added = logger.logs.skip(beforeCount).toList();
        expect(added.length, greaterThanOrEqualTo(minExpectedEntries));
        for (final entry in added) {
          expect(entry.message.contains('my-private'), isFalse);
        }
      },
    );
  });
}
