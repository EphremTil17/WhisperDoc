import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/ui/screens/account/widgets/figure_cell.dart';
import 'package:flutter_client/ui/screens/account/widgets/speech_model_row.dart';
import 'package:flutter_client/ui/shared/widgets/crisp_text.dart';
import 'package:material_ui/material_ui.dart';

/// The column labels over the model picker's rows: Model, and WER (word
/// error rate, what the list is sorted by) over its figures.
class SpeechModelHeader extends StatelessWidget {
  const SpeechModelHeader({super.key});

  static const double _height = 32;

  @override
  Widget build(BuildContext context) {
    final label = AppType.caption.copyWith(color: AppColors.textMuted);

    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.rule)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
        child: SizedBox(
          height: _height,
          child: Row(
            children: [
              Expanded(child: CrispText('Model', style: label)),
              Tooltip(
                message:
                    'Word error rate: the share of words transcribed '
                    'wrong. Lower is better.',
                child: FigureCell(
                  width: SpeechModelRow.werColumn,
                  text: 'WER',
                  style: label,
                ),
              ),
              const SizedBox(width: SpeechModelRow.checkColumn),
            ],
          ),
        ),
      ),
    );
  }
}
