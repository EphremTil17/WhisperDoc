// ignore_for_file: avoid-top-level-members-in-tests, prefer-moving-to-variable
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/logic/models/custom_profile.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/ui/screens/home/dialogs/profile_editor_dialog.dart';

/// Test orchestrator encapsulating dialog presentation, input typing,
/// and action invocations for [ProfileEditorDialog].
class ProfileEditorDialogOrchestrator {
  const ProfileEditorDialogOrchestrator({
    required this.tester,
    required this.mockSettings,
  });

  final WidgetTester tester;
  final SettingsService mockSettings;

  /// Pumps the dialog inside a material scaffold and provider wrapper.
  Future<void> pumpDialog({
    required String slotKey,
    CustomProfile? existing,
  }) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsService>.value(
        value: mockSettings,
        child: MaterialApp(
          home: Scaffold(
            body: ProfileEditorDialog(slotKey: slotKey, existing: existing),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Types [name] into the profile name text field and settles.
  Future<void> enterName(String name) async {
    final nameField = find.byType(TextField).first;
    await tester.enterText(nameField, name);
    await tester.pumpAndSettle();
  }

  /// Types [prompt] into the profile prompt text field and settles.
  Future<void> enterPrompt(String prompt) async {
    final promptField = find.byType(TextField).last;
    await tester.enterText(promptField, prompt);
    await tester.pumpAndSettle();
  }

  /// Taps the Save elevated button and settles.
  Future<void> tapSave() async {
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();
  }

  /// Taps the Delete button and settles.
  Future<void> tapDelete() async {
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
  }

  /// Opens the dialog via [showDialog] from a parent trigger button and settles.
  Future<void> openViaShowDialog({required String slotKey}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => showDialog<void>(
                context: ctx,
                builder: (_) => ChangeNotifierProvider<SettingsService>.value(
                  value: mockSettings,
                  child: ProfileEditorDialog(slotKey: slotKey),
                ),
              ),
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();
  }

  /// Taps the Cancel button and settles.
  Future<void> tapCancel() async {
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  }
}
