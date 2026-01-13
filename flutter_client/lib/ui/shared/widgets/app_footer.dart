import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Footer configuration
class FooterConfig {
  /// Padding from bottom edge of screen
  static const double bottomPadding = 6;

  /// Horizontal padding from edges
  static const double horizontalPadding = 12;
}

/// Minimal footer showing only app version
class AppFooter extends StatelessWidget {
  const AppFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(
        left: FooterConfig.horizontalPadding,
        right: FooterConfig.horizontalPadding,
        bottom: FooterConfig.bottomPadding,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [_VersionDisplay()],
      ),
    );
  }
}

/// Displays dynamic version from pubspec.yaml
class _VersionDisplay extends StatelessWidget {
  const _VersionDisplay();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final version = snapshot.data?.version ?? '...';
        return Text(
          'v$version',
          style: const TextStyle(color: Colors.white24, fontSize: 11),
        );
      },
    );
  }
}
