// ignore_for_file: avoid-top-level-members-in-tests
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/controllers/recording_controller.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/ui/features/recording/widgets/profile_action_button.dart';

/// Test orchestrator encapsulating widget pump cycles, menu overlay transitions,
/// and profile selection interactions for [ProfileActionButton].
class ProfileActionButtonOrchestrator {
  const ProfileActionButtonOrchestrator({
    required this.tester,
    required this.mockSettings,
    required this.mockController,
  });

  final WidgetTester tester;
  final SettingsService mockSettings;
  final RecordingController mockController;

  /// Pumps the [ProfileActionButton] wrapped in necessary mock providers and material scaffold.
  Future<void> pumpButton() async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: mockSettings),
          ChangeNotifierProvider<RecordingController>.value(
            value: mockController,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(bottom: 76),
                child: ProfileActionButton(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Pumps the button and opens the vertical dropdown overlay menu.
  Future<void> openMenu({String buttonLabel = 'Raw'}) async {
    await pumpButton();
    await tester.tap(find.text(buttonLabel));
    await tester.pumpAndSettle();
  }

  /// Taps a specific profile tile by its label and awaits the state transition.
  Future<void> selectProfile(String profileLabel) async {
    await tester.tap(find.text(profileLabel));
    await tester.pumpAndSettle();
  }

  /// Taps the pencil edit icon and awaits the dialog animation.
  Future<void> tapEditIcon() async {
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
  }
}
