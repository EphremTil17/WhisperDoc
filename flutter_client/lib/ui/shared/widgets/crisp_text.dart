import 'package:material_ui/material_ui.dart';
import 'package:flutter_client/ui/shared/widgets/pixel_snap.dart';

/// A [Text] painted on whole device pixels; use it for all UI text.
class CrispText extends StatelessWidget {
  const CrispText(
    this.data, {
    super.key,
    required this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  final String data;
  final TextStyle style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    return PixelSnap(
      child: Text(
        data,
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
      ),
    );
  }
}
