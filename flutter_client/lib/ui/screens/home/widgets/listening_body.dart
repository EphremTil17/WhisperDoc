import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/logic/processors/level_normalizer.dart';
import 'package:flutter_client/services/hardware/audio_service.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/ui/screens/home/widgets/shortcut_line.dart';
import 'package:flutter_client/ui/shared/widgets/pixel_meter.dart';

/// Recording: the pixel meter (unless turned off in Settings) and the
/// shortcut that stops it.
class ListeningBody extends StatelessWidget {
  const ListeningBody({super.key, required this.normalizer});

  static const double _meterHeight = 192;

  final LevelNormalizer normalizer;

  @override
  Widget build(BuildContext context) {
    final showMeter = context.select((SettingsService s) => s.showVisualizer);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showMeter) ...[
          const SizedBox(height: AppSpace.lg),
          SizedBox(
            height: _meterHeight,
            child: PixelMeter(
              levels: context.read<AudioService>().amplitudeStream,
              normalizer: normalizer,
            ),
          ),
          const SizedBox(height: AppSpace.lg),
        ],
        ShortcutLine(
          trailing: 'to stop',
          style: AppType.caption.copyWith(color: AppColors.textMuted),
        ),
      ],
    );
  }
}
