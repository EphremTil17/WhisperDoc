import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Displays dynamic version from pubspec.yaml
class VersionDisplay extends StatelessWidget {
  const VersionDisplay({super.key});

  static const _fontSize = 11.0;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final version = snapshot.data?.version ?? '...';

        return Text(
          'v$version',
          style: const TextStyle(color: Colors.white24, fontSize: _fontSize),
        );
      },
    );
  }
}
