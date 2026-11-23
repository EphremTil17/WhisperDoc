import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/controllers/recording_controller.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/logic/mappers/home_status_mapper.dart';
import 'package:flutter_client/services/transport/websocket_service.dart';
import 'package:flutter_client/ui/screens/home/home_navigation.dart';
import 'package:flutter_client/ui/screens/home/widgets/home_fix_icon.dart';
import 'package:flutter_client/ui/shared/widgets/app_button.dart';
import 'package:flutter_client/ui/shared/widgets/crisp_text.dart';

/// A blocked state: what broke, in one sentence, and the one fix.
class BlockedBody extends StatelessWidget {
  const BlockedBody({super.key, required this.status});

  static const double _fixGap = 20;

  final HomeStatus status;

  static void _run(BuildContext context, HomeFix fix) {
    switch (fix) {
      case HomeFix.openAccount:
        unawaited(HomeNavigation.openAccount(context));
      case HomeFix.openSettings:
        unawaited(HomeNavigation.openSettings(context));
      case HomeFix.retryMicrophone:
        unawaited(context.read<RecordingController>().refreshHardwareStatus());
      case HomeFix.retryServer:
        unawaited(context.read<WebSocketService>().connect());
      case HomeFix.none:
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final headline = status.headline;
    final fixLabel = status.fixLabel;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (headline != null)
          CrispText(headline, style: AppType.title, textAlign: TextAlign.center),
        if (fixLabel != null) ...[
          const SizedBox(height: _fixGap),
          AppButton(
            label: fixLabel,
            leading: Icon(status.fix.actionIcon, size: AppSizes.smallIconSize),
            onPressed: () => _run(context, status.fix),
          ),
        ],
      ],
    );
  }
}
