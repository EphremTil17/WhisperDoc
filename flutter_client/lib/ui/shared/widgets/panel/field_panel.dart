import 'dart:async';

import 'package:flutter_client/infrastructure/theme/app_icons.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/ui/shared/widgets/app_button.dart';
import 'package:flutter_client/ui/shared/widgets/crisp_text.dart';
import 'package:flutter_client/ui/shared/widgets/panel/app_panel.dart';
import 'package:material_ui/material_ui.dart';

/// Edit one text value: a labelled field, a note on what it is for, and
/// Cancel / Save. Saving trims the text, runs [onSave] and goes back.
class FieldPanel extends StatefulWidget {
  const FieldPanel({
    super.key,
    required this.title,
    required this.label,
    required this.initialValue,
    required this.onSave,
    this.hint,
    this.note,
    this.secret = false,
    this.maxLines = 1,
    this.validate,
  });

  final String title;
  final String label;
  final String initialValue;
  final Future<void> Function(String value) onSave;
  final String? hint;
  final String? note;

  /// Masks the text, with a reveal button (API keys).
  final bool secret;

  final int maxLines;

  /// Returns why a value cannot be saved, or null when it can.
  final String? Function(String value)? validate;

  @override
  State<FieldPanel> createState() => _FieldPanelState();
}

class _FieldPanelState extends State<FieldPanel> {
  final TextEditingController _controller = TextEditingController();
  bool _hidden = false;

  @override
  void initState() {
    super.initState();
    _controller.text = widget.initialValue;
    _hidden = widget.secret;
  }

  String? _errorFor(String text) => widget.validate?.call(text.trim());

  Future<void> _save() async {
    final value = _controller.text.trim();
    if (_errorFor(value) != null) return;
    await widget.onSave(value);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final note = widget.note;

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _controller,
      builder: (context, editing, _) {
        final problem = _errorFor(editing.text);
        final canSave = problem == null;
        // An empty field shows no error until there is something to judge.
        final error = editing.text.isEmpty ? null : problem;

        return AppPanel(
          title: widget.title,
          autofocus: false,
          footer: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            spacing: AppSpace.sm,
            children: [
              AppButton(
                label: 'Cancel',
                tone: AppButtonTone.outline,
                onPressed: () => Navigator.of(context).pop(),
              ),
              AppButton(
                label: 'Save',
                onPressed: canSave ? () => unawaited(_save()) : null,
              ),
            ],
          ),
          children: [
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpace.sm,
                right: AppSpace.sm,
                top: AppSpace.xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: AppSpace.sm,
                children: [
                  CrispText(widget.label, style: AppType.label),
                  TextField(
                    controller: _controller,
                    autofocus: true,
                    obscureText: _hidden,
                    maxLines: widget.secret ? 1 : widget.maxLines,
                    minLines: 1,
                    style: AppType.body,
                    onSubmitted: widget.maxLines == 1
                        ? (_) => unawaited(_save())
                        : null,
                    decoration: InputDecoration(
                      hintText: widget.hint,
                      errorText: error,
                      suffixIcon: widget.secret
                          ? IconButton(
                              tooltip: _hidden ? 'Show' : 'Hide',
                              onPressed: () => setState(() => _hidden = !_hidden),
                              icon: Icon(
                                _hidden ? AppIcons.eye : AppIcons.eyeOff,
                                size: AppSizes.smallIconSize,
                              ),
                            )
                          : null,
                    ),
                  ),
                  if (note != null)
                    CrispText(
                      note,
                      style: AppType.caption.copyWith(color: AppColors.textMuted),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
