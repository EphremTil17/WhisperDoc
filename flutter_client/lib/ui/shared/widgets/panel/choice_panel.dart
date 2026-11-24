import 'package:flutter_client/infrastructure/theme/app_icons.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/ui/shared/widgets/caption_cue.dart';
import 'package:flutter_client/ui/shared/widgets/panel/app_panel.dart';
import 'package:flutter_client/ui/shared/widgets/panel/panel_note.dart';
import 'package:flutter_client/ui/shared/widgets/panel/panel_row.dart';
import 'package:material_ui/material_ui.dart';

/// Pick one of [options]: the current one carries a check; picking another
/// applies it and goes back.
class ChoicePanel<T> extends StatelessWidget {
  const ChoicePanel({
    super.key,
    required this.title,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.actions = const [],
    this.cue,
    this.note,
  });

  final String title;

  /// Each option's value and the label shown for it.
  final List<(T, String)> options;
  final T selected;
  final ValueChanged<T> onSelected;
  final List<Widget> actions;

  /// A bracketed status under the options (`[ looking for microphones ]`).
  final String? cue;

  /// A line under the list (what the choice affects).
  final String? note;

  void _pick(BuildContext context, T value) {
    if (value != selected) onSelected(value);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final footnote = note;
    final status = cue;

    return AppPanel(
      title: title,
      actions: actions,
      children: [
        for (final (index, (value, label)) in options.indexed)
          Semantics(
            selected: value == selected,
            inMutuallyExclusiveGroup: true,
            child: PanelRow(
              label: label,
              trailing: value == selected
                  ? const Icon(
                      AppIcons.check,
                      size: AppSizes.smallIconSize,
                      color: AppColors.text,
                    )
                  : null,
              chevron: false,
              rule: index < options.length - 1,
              onTap: () => _pick(context, value),
            ),
          ),
        if (status != null)
          Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Center(child: CaptionCue(status)),
          ),
        if (footnote != null) PanelNote(footnote),
      ],
    );
  }
}
