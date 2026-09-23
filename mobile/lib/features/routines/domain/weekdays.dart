/// Weekday bitmask shared with the server: Monday = 1, Tuesday = 2, ...
/// Sunday = 64 (bit `weekday - 1` for Dart's [DateTime.weekday]).
abstract final class Weekdays {
  static const everyDay = 127;
  static const workdays = 31; // Mon-Fri
  static const weekend = 96; // Sat, Sun

  static int bit(int weekday) => 1 << (weekday - 1);

  static bool includes(int mask, DateTime day) => mask & bit(day.weekday) != 0;

  static const short = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  /// "Every day", "Weekdays", "Weekends" or e.g. "Mon, Wed, Fri".
  static String describe(int mask) {
    switch (mask) {
      case everyDay:
        return 'Every day';
      case workdays:
        return 'Weekdays';
      case weekend:
        return 'Weekends';
    }
    return [for (var d = 1; d <= 7; d++) if (mask & bit(d) != 0) short[d - 1]].join(', ');
  }
}

/// "08:00–17:00", "08:00" or null.
String? formatTimeWindow(String? start, String? end) {
  if (start == null) return null;
  return end == null ? start : '$start–$end';
}

/// Minutes between two HH:MM times, or null.
int? windowMinutes(String? start, String? end) {
  if (start == null || end == null) return null;
  int m(String t) => int.parse(t.substring(0, 2)) * 60 + int.parse(t.substring(3, 5));
  final d = m(end) - m(start);
  return d > 0 ? d : null;
}
