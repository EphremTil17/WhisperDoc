import 'package:material_ui/material_ui.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/ui/shared/widgets/crisp_text.dart';

/// A keyboard shortcut set on a caption band, e.g. `Ctrl Q`.
class Keycap extends StatelessWidget {
  const Keycap(this.label, {super.key, this.style = AppType.caption});

  final String label;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.band),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
        child: CrispText(
          label,
          style: style.copyWith(fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}
