import 'package:flutter_client/infrastructure/theme/app_icons.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/logic/formatters/clock_time.dart';
import 'package:flutter_client/logic/models/speech_model.dart';
import 'package:flutter_client/ui/screens/account/widgets/figure_cell.dart';
import 'package:flutter_client/ui/shared/widgets/crisp_text.dart';
import 'package:flutter_client/ui/shared/widgets/pixel_snap.dart';
import 'package:flutter_client/ui/shared/widgets/press_nudge.dart';
import 'package:material_ui/material_ui.dart';

/// One model in the OpenRouter picker: its name, and beneath it in small
/// type its maker, live latency, and "retires …" or "keeps data" when they
/// apply; its word error rate in the right-hand column (the list's order),
/// then a check when it is the one in use.
class SpeechModelRow extends StatelessWidget {
  const SpeechModelRow({
    super.key,
    required this.model,
    required this.selected,
    required this.onTap,
    this.wordErrorRate,
    this.latency,
    this.latencyLoading = false,
    this.rule = true,
  });

  /// Column widths, shared with the header so its label sits over figures.
  static const double werColumn = 44;
  static const double checkColumn = AppSizes.smallIconSize + AppSpace.sm;

  /// Shown in the WER column for a model never measured.
  static const String noFigure = '—';

  static const String _dot = ' • ';

  static const BoxDecoration _ruled = BoxDecoration(
    border: Border(bottom: BorderSide(color: AppColors.rule)),
  );

  final SpeechModel model;
  final bool selected;
  final VoidCallback onTap;

  /// Artificial Analysis word error rate in percent; null when not measured.
  final double? wordErrorRate;

  /// OpenRouter's typical median latency; null when unknown.
  final Duration? latency;

  /// Figures are still being read: a missing one shows `…`, not nothing.
  final bool latencyLoading;

  /// Draws the 1px rule beneath; off for the last row.
  final bool rule;

  @override
  Widget build(BuildContext context) {
    final wer = wordErrorRate;
    final speed = latency;
    final retires = model.retiresOn;
    final small = AppType.caption.copyWith(color: AppColors.textMuted);
    // The second line, in order; flags keep their colour.
    final details = <(String, Color?)>[
      if (model.maker.isNotEmpty) (model.maker, null),
      if (speed != null)
        (ClockTime.latency(speed), null)
      else if (latencyLoading)
        ('…', null),
      if (retires != null)
        ('retires ${ClockTime.dayMonth(retires)}', AppColors.update),
      if (!model.zdr) ('keeps data', AppColors.alert),
    ];

    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      excludeSemantics: true,
      label: [
        model.name,
        for (final (text, _) in details) text,
        if (wer != null) 'word error rate $wer%',
      ].join(', '),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.controlAll,
        hoverColor: AppColors.band,
        highlightColor: AppColors.band,
        focusColor: AppColors.band,
        splashFactory: NoSplash.splashFactory,
        child: DecoratedBox(
          decoration: rule ? _ruled : const BoxDecoration(),
          child: PressNudge(
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CrispText(
                          model.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.body,
                        ),
                        if (details.isNotEmpty)
                          PixelSnap(
                            child: Text.rich(
                              TextSpan(
                                style: small,
                                children: [
                                  for (final (i, (text, color))
                                      in details.indexed) ...[
                                    if (i > 0) const TextSpan(text: _dot),
                                    TextSpan(
                                      text: text,
                                      style: color == null
                                          ? null
                                          : TextStyle(color: color),
                                    ),
                                  ],
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                  FigureCell(
                    width: werColumn,
                    text: wer == null ? noFigure : '$wer%',
                    style: AppType.figure.copyWith(
                      color: selected ? AppColors.text : AppColors.textMuted,
                    ),
                  ),
                  SizedBox(
                    width: checkColumn,
                    child: selected
                        ? const Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: Icon(
                              AppIcons.check,
                              size: AppSizes.smallIconSize,
                              color: AppColors.text,
                            ),
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
