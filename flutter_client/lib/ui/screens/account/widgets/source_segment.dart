import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/logic/models/transcription_source.dart';
import 'package:flutter_client/ui/shared/widgets/crisp_text.dart';
import 'package:flutter_client/ui/shared/widgets/source_glyph.dart';
import 'package:material_ui/material_ui.dart';

/// One choice in the [SourceSelector]: the source's mark and short name.
class SourceSegment extends StatelessWidget {
  const SourceSegment({
    super.key,
    required this.source,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.hint,
  });

  final TranscriptionSource source;
  final String label;
  final bool selected;

  /// Null when the segment can't be chosen (already chosen, or locked).
  final VoidCallback? onTap;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final locked = onTap == null && !selected;
    final tone = switch ((selected, locked)) {
      (true, _) => AppColors.text,
      (false, true) => AppColors.iconFaint,
      (false, false) => AppColors.textMuted,
    };

    // One node per segment, holding its tooltip: Flutter keeps only the
    // first tooltip a merged node absorbs, so the others' bubbles would have
    // no parent, and Windows rejects every accessibility update from then on
    // ("N will not be in the tree"; flutter/flutter#197194). The tooltip also
    // stays outside the excluded subtree, which would cut it off too.
    return Semantics(
      container: true,
      child: Tooltip(
        message: hint,
        child: Semantics(
          button: true,
          selected: selected,
          inMutuallyExclusiveGroup: true,
          label: source.label,
          onTap: onTap,
          excludeSemantics: true,
          child: Material(
            color: selected ? AppColors.band : Colors.transparent,
            child: InkWell(
              onTap: onTap,
              hoverColor: AppColors.band,
              focusColor: AppColors.band,
              highlightColor: AppColors.band,
              splashFactory: NoSplash.splashFactory,
              child: SizedBox(
                height: AppSizes.controlHeight,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  spacing: AppSpace.sm,
                  children: [
                    SourceGlyph(source, color: tone),
                    Flexible(
                      child: CrispText(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.caption.copyWith(
                          color: tone,
                          fontWeight: selected ? FontWeight.w600 : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
