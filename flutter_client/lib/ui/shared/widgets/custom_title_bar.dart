import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/ui/shared/widgets/crisp_text.dart';
import 'package:flutter_client/ui/shared/widgets/window_button.dart';
import 'package:window_manager/window_manager.dart';

/// The window's own title bar: name on the left, an optional [trailing]
/// control (the account indicator), then minimize and close. The empty
/// stretch is the drag area.
class CustomTitleBar extends StatelessWidget {
  const CustomTitleBar({super.key, this.trailing});

  final Widget? trailing;

  static const double _endPadding = 4;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppSizes.titleBar,
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              // Keep taps from passing through the transparent title bar and
              // clear any active text focus while the user interacts with it.
              onTap: () => FocusScope.of(context).unfocus(),
              child: DragToMoveArea(
                child: ColoredBox(
                  color: Colors.transparent,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(start: AppSpace.lg),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: CrispText(
                        'WhisperDoc',
                        style: AppType.caption.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          ?trailing,
          WindowButton(
            icon: LucideIcons.minus,
            tooltip: 'Minimize',
            onPressed: () => WindowManager.instance.getCurrent()?.minimize(),
          ),
          WindowButton(
            icon: LucideIcons.x,
            tooltip: 'Close',
            isClose: true,
            onPressed: () => WindowManager.instance.getCurrent()?.close(),
          ),
          const SizedBox(width: _endPadding),
        ],
      ),
    );
  }
}
