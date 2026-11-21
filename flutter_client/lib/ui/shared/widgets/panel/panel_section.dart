import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/ui/shared/widgets/crisp_text.dart';
import 'package:material_ui/material_ui.dart';

/// A labelled group of panel rows: `Recording`, then its rows.
class PanelSection extends StatelessWidget {
  const PanelSection({super.key, required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpace.sm,
            right: AppSpace.sm,
            top: AppSpace.xl,
            bottom: AppSpace.xs,
          ),
          child: CrispText(label, style: AppType.label),
        ),
        ...children,
      ],
    );
  }
}
