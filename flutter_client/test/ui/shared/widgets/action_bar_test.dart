// ignore_for_file: avoid-late-keyword, prefer-match-file-name
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/controllers/recording_controller.dart';
import 'package:flutter_client/logic/models/dictation_profile.dart';
import 'package:flutter_client/services/auth/auth_service.dart';
import 'package:flutter_client/services/transcription/groq_transcription_service.dart';
import 'package:flutter_client/services/transport/handshake_state_machine.dart';
import 'package:flutter_client/services/transport/transport_security_service.dart';
import 'package:flutter_client/services/transport/websocket_service.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/services/utility/update_service.dart';
import 'package:flutter_client/ui/features/recording/widgets/profile_action_button.dart';
import 'package:flutter_client/ui/shared/widgets/action_bar.dart';

class _MockRecordingController extends Mock
    with ChangeNotifier
    implements RecordingController {}

class _MockSettingsService extends Mock
    with ChangeNotifier
    implements SettingsService {}

class _MockWebSocketService extends Mock
    with ChangeNotifier
    implements WebSocketService {}

class _MockAuthService extends Mock
    with ChangeNotifier
    implements AuthService {}

class _MockUpdateService extends Mock
    with ChangeNotifier
    implements UpdateService {}

class _MockGroqTranscriptionService extends Mock
    with ChangeNotifier
    implements GroqTranscriptionService {}

class _MockHandshakeStateMachine extends Mock
    implements HandshakeStateMachine {}

abstract final class _TestConstants {
  static const int lockableControlCount = 6;
  static const double lockedOpacity = 0.35;
  static void noop() {
    return;
  }
}

void main() {
  late _MockRecordingController mockController;
  late _MockSettingsService mockSettings;
  late _MockWebSocketService mockWs;
  late _MockAuthService mockAuth;
  late _MockUpdateService mockUpdate;
  late _MockGroqTranscriptionService mockGroq;

  setUp(() {
    mockController = _MockRecordingController();
    mockSettings = _MockSettingsService();
    mockWs = _MockWebSocketService();
    mockAuth = _MockAuthService();
    mockUpdate = _MockUpdateService();
    mockGroq = _MockGroqTranscriptionService();

    when(() => mockController.isSessionActive).thenReturn(false);
    when(() => mockController.showSilenceWarning).thenReturn(false);

    when(() => mockSettings.isGroqMode).thenReturn(true);
    when(() => mockSettings.dictationProfile).thenReturn(DictationProfile.raw);
    when(() => mockSettings.customProfiles).thenReturn([]);
    when(() => mockSettings.nextFreeCustomSlot()).thenReturn('custom1');
    when(() => mockSettings.cachedGroqApiKey).thenReturn('test-key');

    when(() => mockWs.status).thenReturn(ConnectionStatus.disconnected);
    when(() => mockWs.hasValidCredentials).thenReturn(false);
    final mockHandshake = _MockHandshakeStateMachine();
    when(() => mockHandshake.state).thenReturn(HandshakeState.locked);
    when(() => mockWs.handshakeState).thenReturn(mockHandshake);
    when(() => mockWs.securityStatus).thenReturn(SecurityStatus.secure);
    when(() => mockUpdate.status).thenReturn(UpdateStatus.upToDate);

    when(() => mockGroq.hasValidCredentials).thenReturn(true);
    when(() => mockGroq.status).thenReturn(GroqTranscriptionStatus.idle);
  });

  Widget buildActionBar() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<RecordingController>.value(
          value: mockController,
        ),
        ChangeNotifierProvider<SettingsService>.value(value: mockSettings),
        ChangeNotifierProvider<WebSocketService>.value(value: mockWs),
        ChangeNotifierProvider<AuthService>.value(value: mockAuth),
        ChangeNotifierProvider<UpdateService>.value(value: mockUpdate),
        ChangeNotifierProvider<GroqTranscriptionService>.value(value: mockGroq),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: ActionBar(
            isIncognitoMode: false,
            onIncognitoTap: _TestConstants.noop,
          ),
        ),
      ),
    );
  }

  testWidgets(
    'all 6 controls are active (ignoring: false, opacity: 1.0) when idle',
    (tester) async {
      await tester.pumpWidget(buildActionBar());
      await tester.pump(const Duration(milliseconds: 200));

      final lockOpacities = find.byWidgetPredicate(
        (w) =>
            w is AnimatedOpacity &&
            w.duration == const Duration(milliseconds: 150),
      );
      expect(lockOpacities, findsNWidgets(_TestConstants.lockableControlCount));

      final opacitiesList = tester.widgetList<AnimatedOpacity>(lockOpacities);
      for (final ao in opacitiesList) {
        expect(ao.opacity, 1.0);
      }

      // Each lock opacity has an ancestor IgnorePointer with ignoring == false
      for (var i = 0; i < _TestConstants.lockableControlCount; i++) {
        final ancestorIp = find.ancestor(
          of: lockOpacities.at(i),
          matching: find.byType(IgnorePointer),
        );
        final ipWidget = tester.widget<IgnorePointer>(ancestorIp.first);
        expect(ipWidget.ignoring, isFalse);
      }
    },
  );

  testWidgets(
    'all 6 controls are locked (ignoring: true, opacity: 0.35) during session',
    (tester) async {
      when(() => mockController.isSessionActive).thenReturn(true);

      await tester.pumpWidget(buildActionBar());
      await tester.pump(const Duration(milliseconds: 200));

      final lockOpacities = find.byWidgetPredicate(
        (w) =>
            w is AnimatedOpacity &&
            w.duration == const Duration(milliseconds: 150),
      );
      final expectedLockableCount = findsNWidgets(
        _TestConstants.lockableControlCount,
      );
      expect(lockOpacities, expectedLockableCount);

      final opacitiesList = tester.widgetList<AnimatedOpacity>(lockOpacities);
      for (final ao in opacitiesList) {
        expect(ao.opacity, _TestConstants.lockedOpacity);
      }

      for (var i = 0; i < _TestConstants.lockableControlCount; i++) {
        final ancestorIp = find.ancestor(
          of: lockOpacities.at(i),
          matching: find.byType(IgnorePointer),
        );
        final ipWidget = tester.widget<IgnorePointer>(ancestorIp.first);
        expect(ipWidget.ignoring, isTrue);
      }

      // Tooltips reading "Unavailable while recording" should be present on outer boundary
      expect(
        find.byWidgetPredicate(
          (w) => w is Tooltip && w.message == 'Unavailable while recording',
        ),
        expectedLockableCount,
      );
    },
  );

  testWidgets(
    'silence warning button remains live and excluded from lock during active session',
    (tester) async {
      when(() => mockController.isSessionActive).thenReturn(true);
      when(() => mockController.showSilenceWarning).thenReturn(true);

      await tester.pumpWidget(buildActionBar());
      await tester.pump(const Duration(milliseconds: 200));

      // Warning icon is visible
      final warningIconFinder = find.byIcon(Icons.warning_amber_rounded);
      expect(warningIconFinder, findsOneWidget);

      // Finding IgnorePointer ancestors of the warning icon
      final ancestorIgnorePointer = find.ancestor(
        of: warningIconFinder,
        matching: find.byWidgetPredicate(
          (w) => w is IgnorePointer && w.ignoring,
        ),
      );

      // Warning button must NOT be inside an IgnorePointer with ignoring == true
      expect(ancestorIgnorePointer, findsNothing);
    },
  );

  testWidgets(
    'profile button is locked with Available in Groq Cloud mode tooltip in backend mode',
    (tester) async {
      when(() => mockSettings.isGroqMode).thenReturn(false);
      when(() => mockController.isSessionActive).thenReturn(false);

      await tester.pumpWidget(buildActionBar());
      await tester.pump(const Duration(milliseconds: 200));

      final profileFinder = find.byType(ProfileActionButton);
      expect(profileFinder, findsOneWidget);

      final ancestorIp = find.ancestor(
        of: profileFinder,
        matching: find.byWidgetPredicate(
          (w) => w is IgnorePointer && w.ignoring,
        ),
      );
      expect(ancestorIp, findsOneWidget);

      expect(
        find.byWidgetPredicate(
          (w) => w is Tooltip && w.message == 'Available in Groq Cloud mode',
        ),
        findsOneWidget,
      );
    },
  );
}
