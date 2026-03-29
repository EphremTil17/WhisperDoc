import 'package:flutter/material.dart';
import 'package:flutter_client/ui/shared/widgets/window_button.dart';
import 'package:window_manager/window_manager.dart';

class CustomTitleBar extends StatelessWidget {
  const CustomTitleBar({super.key});

  static const _titleBarHeight = 32.0;
  static const _dragRegionLeftPadding = 16.0;
  static const _trailingGap = SizedBox(width: 8);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _titleBarHeight,
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              // Keep taps from passing through the transparent title bar and
              // clear any active text focus while the user interacts with it.
              onTap: () => FocusScope.of(context).unfocus(),
              child: DragToMoveArea(
                child: Container(
                  color: Colors.transparent,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: _dragRegionLeftPadding),
                ),
              ),
            ),
          ),
          WindowButton(
            icon: Icons.minimize,
            onPressed: () => windowManager.minimize(),
          ),
          WindowButton(
            icon: Icons.close,
            isClose: true,
            onPressed: () => windowManager.close(),
          ),
          _trailingGap,
        ],
      ),
    );
  }
}
