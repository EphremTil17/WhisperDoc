import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/services/utility/settings_service.dart';

/// Displays the app version, read once at startup by [SettingsService].
class VersionDisplay extends StatelessWidget {
  const VersionDisplay({super.key});

  static const _fontSize = 11.0;

  @override
  Widget build(BuildContext context) {
    final version = context.select((SettingsService s) => s.appVersion);

    return Text(
      'v$version',
      style: const TextStyle(color: Colors.white24, fontSize: _fontSize),
    );
  }
}
