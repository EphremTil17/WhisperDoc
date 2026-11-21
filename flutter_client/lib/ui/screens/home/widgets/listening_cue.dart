import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_client/logic/formatters/clock_time.dart';
import 'package:flutter_client/logic/mappers/home_status_mapper.dart';
import 'package:flutter_client/ui/shared/widgets/caption_cue.dart';

/// The recording cue with its elapsed time, `[ listening · 0:07 ]`.
///
/// Owns a one-second timer so only this cue rebuilds while recording.
class ListeningCue extends StatefulWidget {
  const ListeningCue({super.key, required this.label, required this.tone});

  final String label;
  final CueTone tone;

  @override
  State<ListeningCue> createState() => _ListeningCueState();
}

class _ListeningCueState extends State<ListeningCue> {
  final Stopwatch _clock = Stopwatch()..start();
  Duration _elapsed = Duration.zero;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => _elapsed = _clock.elapsed),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CaptionCue(
      '${widget.label} · ${ClockTime.minutesSeconds(_elapsed)}',
      tone: widget.tone,
    );
  }
}
