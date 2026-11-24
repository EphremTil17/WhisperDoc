import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/ui/shared/widgets/crisp_text.dart';
import 'package:material_ui/material_ui.dart';

/// A caption line in a panel: what a choice affects, or (in [color]) what
/// is wrong.
class PanelNote extends StatelessWidget {
  const PanelNote(this.text, {super.key, this.color = AppColors.textMuted});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpace.sm),
      child: CrispText(text, style: AppType.caption.copyWith(color: color)),
    );
  }
}
