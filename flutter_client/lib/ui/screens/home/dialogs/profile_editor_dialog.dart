import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import 'package:flutter_client/infrastructure/theme/app_theme.dart';
import 'package:flutter_client/logic/models/custom_profile.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/ui/shared/widgets/glass_dialog.dart';

/// Modal dialog for creating and editing user custom dictation profiles.
/// Built on the standard [GlassDialog] shell.
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
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _promptController = TextEditingController();

  static const double _dialogMaxWidth = 380;
  static const double _fieldBorderRadius = 8;
  static const double _fieldBorderAlpha = 0.15;
  static const double _fieldFillAlpha = 0.05;
  static const double _disabledControlAlpha = 0.08;
  static const double _safetyBgAlpha = 0.03;
  static const double _safetyBorderAlpha = 0.08;
  static const int _promptMaxLines = 6;
  static const double _buttonBorderRadius = 6;
  static const double _counterFontSize = 10;
  static const double _buttonFontSize = 11;

  bool get _isEditMode => widget.existing != null;
  bool _canSave = false;

  bool _evaluateCanSave() {
    final name = _nameController.text.trim();
    final prompt = _promptController.text.trim();

    return name.isNotEmpty && prompt.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    final initialName =
        widget.existing?.name ??
        CustomProfile.defaultNameForSlot(widget.slotKey);
    final initialPrompt = widget.existing?.userPrompt ?? '';

    _nameController.text = initialName;
    _promptController.text = initialPrompt;
    _canSave = _evaluateCanSave();

    _nameController.addListener(_onTextChanged);
    _promptController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    setState(() {
      _canSave = _evaluateCanSave();
    });
  }

  @override
  void dispose() {
    _nameController.removeListener(_onTextChanged);
    _promptController.removeListener(_onTextChanged);
    _nameController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  void _onSave() {
    unawaited(_handleSave());
  }

  void _onDelete() {
    unawaited(_handleDelete());
  }

  Future<void> _handleSave() async {
    if (!_canSave) return;

    final profile = CustomProfile(
      storageKey: widget.slotKey,
      name: _nameController.text.trim(),
      userPrompt: _promptController.text.trim(),
    );

    final settings = context.read<SettingsService>();
    await settings.saveCustomProfile(profile);
    await settings.setDictationProfile(profile);

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _handleDelete() async {
    final settings = context.read<SettingsService>();
    await settings.deleteCustomProfile(widget.slotKey);

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final promptChars = _promptController.text.length;
    final estimatedTokens =
        (promptChars / AppConstants.groqTransformCharsPerToken).ceil();

    final borderSide = BorderSide(
      color: Colors.white.withValues(alpha: _fieldBorderAlpha),
    );
    const borderRadius = BorderRadius.all(Radius.circular(_fieldBorderRadius));
    final defaultBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: borderSide,
    );
    const focusedBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(color: AppTheme.crimsonPrimary),
    );
    final fieldFillColor = Colors.white.withValues(alpha: _fieldFillAlpha);
    final disabledBgColor = Colors.white.withValues(
      alpha: _disabledControlAlpha,
    );

    return GlassDialog(
      title: _isEditMode ? 'Edit Custom Profile' : 'New Custom Profile',
      shrinkWrap: true,
      maxWidth: _dialogMaxWidth,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile Name Input
            const Text(
              'PROFILE NAME',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _nameController,
              maxLength: AppConstants.customProfileMaxNameLength,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                height: 1.2,
              ),
              decoration: InputDecoration(
                isDense: true,
                counterText: '',
                hintText: 'e.g. Jira Ticket, Executive Email',
                hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                filled: true,
                fillColor: fieldFillColor,
                contentPadding: const EdgeInsets.all(12),
                border: defaultBorder,
                enabledBorder: defaultBorder,
                focusedBorder: focusedBorder,
              ),
            ),
            const SizedBox(height: 14),

            // System Prompt Input
            const Text(
              'SYSTEM PROMPT',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _promptController,
              maxLength: AppConstants.customProfileMaxPromptLength,
              maxLines: _promptMaxLines,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                height: 1.4,
              ),
              decoration: InputDecoration(
                isDense: true,
                counterText: '',
                hintText:
                    "Describe how the transcript should be rewritten, e.g. 'Rewrite into clean bullet points with zero conversational filler.'",
                hintStyle: const TextStyle(color: Colors.white30, fontSize: 11),
                filled: true,
                fillColor: fieldFillColor,
                contentPadding: const EdgeInsets.all(10),
                border: defaultBorder,
                enabledBorder: defaultBorder,
                focusedBorder: focusedBorder,
              ),
            ),
            const SizedBox(height: 4),

            // Live Character / Token Counter
            Text(
              '$promptChars / ${AppConstants.customProfileMaxPromptLength} chars · ~$estimatedTokens tokens',
              style: const TextStyle(
                color: Colors.white38,
                fontSize: _counterFontSize,
              ),
            ),
            const SizedBox(height: 8),

            // Safety Preamble Notice
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: _safetyBgAlpha),
                borderRadius: const BorderRadius.all(Radius.circular(6)),
                border: Border.all(
                  color: Colors.white.withValues(alpha: _safetyBorderAlpha),
                ),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.security_rounded, size: 13, color: Colors.white38),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'The transcript is passed strictly as data, never as instructions. Your prompt is appended to WhisperDoc\'s safety preamble.',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 9.5,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Delete action (Edit mode only)
          if (_isEditMode)
            TextButton.icon(
              onPressed: _onDelete,
              icon: const Icon(
                Icons.delete_outline_rounded,
                size: 14,
                color: AppTheme.crimsonPrimary,
              ),
              label: const Text(
                'Delete',
                style: TextStyle(
                  color: AppTheme.crimsonPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
            )
          else
            const SizedBox.shrink(),

          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _canSave ? _onSave : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.crimsonPrimary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: disabledBgColor,
                  disabledForegroundColor: Colors.white38,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: const BorderRadius.all(
                      Radius.circular(_buttonBorderRadius),
                    ),
                    side: BorderSide(
                      color: _canSave ? Colors.transparent : disabledBgColor,
                    ),
                  ),
                ),
                child: Text(
                  'Save',
                  style: TextStyle(
                    color: _canSave ? Colors.white : Colors.white38,
                    fontSize: _buttonFontSize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
