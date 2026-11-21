/// Wall-clock formatting shared by logs and history.
abstract final class ClockTime {
  static const int _componentWidth = 2;

  /// `HH:mm:ss`, zero-padded, in the time zone of [time].
  static String hms(DateTime time) =>
      '${_pad(time.hour)}:${_pad(time.minute)}:${_pad(time.second)}';

  /// `m:ss` for an elapsed [duration], e.g. a recording timer.
  static String minutesSeconds(Duration duration) =>
      '${duration.inMinutes}:${_pad(duration.inSeconds % Duration.secondsPerMinute)}';

  static String _pad(int value) =>
      value.toString().padLeft(_componentWidth, '0');
}
