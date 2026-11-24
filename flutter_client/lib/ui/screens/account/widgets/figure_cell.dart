import 'package:flutter_client/ui/shared/widgets/crisp_text.dart';
import 'package:material_ui/material_ui.dart';

/// A fixed-width table cell with its text against the end edge, so figures
/// and their column label line up whatever their length.
class FigureCell extends StatelessWidget {
  const FigureCell({
    super.key,
    required this.width,
    required this.text,
    required this.style,
  });

  final double width;
  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      // CrispText sizes to its text, so the end alignment comes from here.
      // The height factor keeps the cell as tall as its text in the row.
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        heightFactor: 1,
        child: CrispText(text, maxLines: 1, style: style),
      ),
    );
  }
}
