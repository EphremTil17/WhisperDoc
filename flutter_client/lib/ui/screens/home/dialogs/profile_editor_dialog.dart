import 'dart:async';

import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import 'package:flutter_client/infrastructure/theme/app_icons.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/logic/models/custom_profile.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/ui/shared/widgets/app_button.dart';
import 'package:flutter_client/ui/shared/widgets/app_dialog.dart';
import 'package:flutter_client/ui/shared/widgets/app_link.dart';
import 'package:flutter_client/ui/shared/widgets/confirm_dialog.dart';
import 'package:flutter_client/ui/shared/widgets/crisp_text.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Creates or edits a custom output style: a name and the instructions the
/// transcript is rewritten with. Saving also makes it the active style.
class ProfileEditorDialog extends StatefulWidget {
  const ProfileEditorDialog({super.key, required this.slotKey, this.existing});

  /// The slot key (`custom1`, `custom2`, `custom3`) being created or edited.
  final String slotKey;

  /// Existing profile data when in edit mode. Null in create mode.
  final CustomProfile? existing;

  @override
  State<ProfileEditorDialog> createState() => _ProfileEditorDialogState();
}

class _ProfileEditorDialogState extends State<ProfileEditorDialog> {
  static const double _maxWidth = 380;
  static const int _promptMinLines = 4;
  static const int _promptMaxLines = 6;
  static const double _noteIconSize = 14;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _promptController = TextEditingController();

  /// Either field changing rebuilds the counter and the Save button.
  Listenable _fields = Listenable.merge(const []);

  bool get _isEditMode => widget.existing != null;

  bool get _canSave =>
      _nameController.text.trim().isNotEmpty &&
      _promptController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _nameController.text =
        widget.existing?.name ??
        CustomProfile.defaultNameForSlot(widget.slotKey);
    _promptController.text = widget.existing?.userPrompt ?? '';
    _fields = Listenable.merge([_nameController, _promptController]);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_canSave) return;
    final profile = CustomProfile(
      storageKey: widget.slotKey,
      name: _nameController.text.trim(),
      userPrompt: _promptController.text.trim(),
    );
    final settings = context.read<SettingsService>();
    await settings.saveCustomProfile(profile);
    await settings.setDictationProfile(profile);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final settings = context.read<SettingsService>();
    final confirmed = await ConfirmDialog.ask(
      context,
      title: 'Delete this style?',
      message: 'Its name and instructions are removed for good.',
      confirmLabel: 'Delete',
    );
    if (!confirmed) return;
    await settings.deleteCustomProfile(widget.slotKey);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final muted = AppType.caption.copyWith(color: AppColors.textMuted);

    return ListenableBuilder(
      listenable: _fields,
      builder: (context, _) {
        final chars = _promptController.text.length;

        return AppDialog(
          title: _isEditMode ? 'Edit style' : 'New style',
          shrinkWrap: true,
          maxWidth: _maxWidth,
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const CrispText('Name', style: AppType.label),
                const SizedBox(height: AppSpace.sm),
                TextField(
                  controller: _nameController,
                  maxLength: AppConstants.customProfileMaxNameLength,
                  style: AppType.body,
                  decoration: const InputDecoration(
                    counterText: '',
                    hintText: 'e.g. Jira ticket',
                  ),
                ),
                const SizedBox(height: AppSpace.lg),
                const CrispText('Instructions', style: AppType.label),
                const SizedBox(height: AppSpace.sm),
                TextField(
                  controller: _promptController,
                  maxLength: AppConstants.customProfileMaxPromptLength,
                  minLines: _promptMinLines,
                  maxLines: _promptMaxLines,
                  style: AppType.body,
                  decoration: const InputDecoration(
                    counterText: '',
                    hintText:
                        'How to rewrite the transcript, '
                        'e.g. clean bullet points, no filler.',
                  ),
                ),
                const SizedBox(height: AppSpace.xs),
                CrispText(
                  '$chars / ${AppConstants.customProfileMaxPromptLength} chars',
                  style: muted,
                ),
                const SizedBox(height: AppSpace.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: AppSpace.sm,
                  children: [
                    const Icon(
                      AppIcons.shieldCheck,
                      size: _noteIconSize,
                      color: AppColors.textMuted,
                    ),
                    Expanded(
                      child: CrispText(
                        'Only these instructions shape the text. Anything '
                        'you say while recording is never taken as one.',
                        style: muted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          footer: Row(
            spacing: AppSpace.sm,
            children: [
              if (_isEditMode)
                AppLink(
                  label: 'Delete',
                  color: AppColors.alert,
                  onPressed: () => unawaited(_delete()),
                ),
              const Spacer(),
              AppButton(
                label: 'Cancel',
                tone: AppButtonTone.outline,
                onPressed: () => Navigator.of(context).pop(),
              ),
              AppButton(
                label: 'Save',
                onPressed: _canSave ? () => unawaited(_save()) : null,
              ),
            ],
          ),
        );
      },
    );
  }
}
