import 'package:material_ui/material_ui.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/ui/shared/widgets/custom_title_bar.dart';
import 'package:flutter_client/ui/shared/widgets/crisp_text.dart';

/// The app's first frame: its ground and title bar, so the window opens
/// already looking like WhisperDoc while services start. Shows [error] if
/// startup fails, so the window never sits blank.
class BootScreen extends StatelessWidget {
  final Object? error;

  const BootScreen({super.key, this.error});

  @override
  Widget build(BuildContext context) {
    final failure = error;

    return Scaffold(
      body: Column(
        children: [
          const CustomTitleBar(),
          if (failure != null)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpace.xl),
                  child: CrispText(
                    'WhisperDoc could not start.\n\n$failure',
                    textAlign: TextAlign.center,
                    style: AppType.caption.copyWith(color: AppColors.textMuted),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
