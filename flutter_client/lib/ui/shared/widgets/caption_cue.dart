import 'package:material_ui/material_ui.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/logic/mappers/home_status_mapper.dart';
import 'package:flutter_client/ui/shared/widgets/crisp_text.dart';

/// A status cue written like a caption sound description: `[ ready ]`.
///
/// [CueTone.live] leads with a record dot; [CueTone.alert] colours the text
/// and an optional [icon] crimson.
class CaptionCue extends StatelessWidget {
  const CaptionCue(
    this.text, {
    super.key,
    this.tone = CueTone.muted,
    this.icon,
  });

  static const double _dotSize = 8;
  static const double _iconSize = 14;

  final String text;
  final CueTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final color = tone == CueTone.muted ? AppColors.textMuted : AppColors.alert;
    final leading = icon;

    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: AppSpace.sm,
      children: [
        if (tone == CueTone.live)
          const DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.record,
              shape: BoxShape.circle,
            ),
            child: SizedBox.square(dimension: _dotSize),
          ),
        if (leading != null) Icon(leading, size: _iconSize, color: color),
        CrispText('[ $text ]', style: AppType.caption.copyWith(color: color)),
      ],
    );
  }
}
