import 'package:flutter/material.dart';
import 'package:flutter_client/ui/shared/widgets/version_display.dart';

/// Minimal footer showing status and app version
class AppFooter extends StatelessWidget {
  const AppFooter({super.key});

  static const _bottomPadding = 6.0;
  static const _horizontalPadding = 12.0;

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(
        left: _horizontalPadding,
        right: _horizontalPadding,
        bottom: _bottomPadding,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [VersionDisplay()],
      ),
    );
  }
}
