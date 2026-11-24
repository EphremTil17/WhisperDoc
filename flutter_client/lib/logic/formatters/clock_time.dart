/// Wall-clock formatting shared by logs and history.
abstract final class ClockTime {
  static const int _componentWidth = 2;
  static const int _millisWidth = 3;
  static const List<String> _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// `HH:mm:ss`, zero-padded, in the time zone of [time].
  static String hms(DateTime time) =>
      '${_pad(time.hour)}:${_pad(time.minute)}:${_pad(time.second)}';

  /// `HH:mm:ss.SSS`: [hms] with milliseconds, for logs that are compared
  /// against each other.
  static String hmsMillis(DateTime time) =>
      '${hms(time)}.${time.millisecond.toString().padLeft(_millisWidth, '0')}';

  /// When a history entry was made, as specific as it needs to be:
  /// `14:32` today, `Yesterday 14:32`, `20 Nov 14:32` before that.
  static String stamp(DateTime time, DateTime now) {
    final clock = '${_pad(time.hour)}:${_pad(time.minute)}';
    // Calendar days, compared as UTC dates so a DST change cannot shorten one.
    final days = DateTime.utc(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime.utc(time.year, time.month, time.day)).inDays;

    return switch (days) {
      0 => clock,
      1 => 'Yesterday $clock',
      _ => '${dayMonth(time)} $clock',
    };
  }

  /// `22 Dec`.
  static String dayMonth(DateTime time) =>
      '${time.day} ${_months[time.month - 1]}';

  /// A response time as people read it: `290 ms` to the nearest 10 ms
  /// (`<10 ms` below that), `1.4 s` from a second up (995 ms included,
  /// which would otherwise round to `1000 ms`).
  static String latency(Duration latency) {
    const tens = 10;
    final ms = latency.inMilliseconds;
    final rounded = (ms / tens).round() * tens;
    if (rounded < tens) return '<$tens ms';
    if (rounded < Duration.millisecondsPerSecond) return '$rounded ms';

    return '${(ms / Duration.millisecondsPerSecond).toStringAsFixed(1)} s';
  }

  /// `m:ss` for an elapsed [duration], e.g. a recording timer.
  static String minutesSeconds(Duration duration) =>
      '${duration.inMinutes}:${_pad(duration.inSeconds % Duration.secondsPerMinute)}';

  /// Plain relative age: `just now`, `1 min ago`, `12 min ago`, `3 h ago`.
  static String ago(Duration age) {
    if (age.inMinutes < 1) return 'just now';
    if (age.inHours < 1) return '${age.inMinutes} min ago';

    return '${age.inHours} h ago';
  }

  static String _pad(int value) =>
      value.toString().padLeft(_componentWidth, '0');
}
