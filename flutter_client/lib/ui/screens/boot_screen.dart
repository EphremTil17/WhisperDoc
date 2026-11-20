import 'package:material_ui/material_ui.dart';
import 'package:flutter_client/infrastructure/theme/app_theme.dart';
import 'package:flutter_client/ui/shared/widgets/custom_title_bar.dart';

/// The app's first frame: its background and title bar, so the window opens
/// already looking like WhisperDoc while services start. Shows [error] if
/// startup fails, so the window never sits blank.
class BootScreen extends StatelessWidget {
  final Object? error;

  const BootScreen({super.key, this.error});

  @override
  Widget build(BuildContext context) {
    final failure = error;

    return Scaffold(
      body: DecoratedBox(
        decoration: AppTheme.mainGradient,
        child: Column(
          children: [
            const CustomTitleBar(),
            if (failure != null)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'WhisperDoc could not start.\n\n$failure',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
