import '../../../core/db/app_database.dart';
import '../../../core/time.dart';
import 'weekdays.dart';

abstract final class Frequency {
  static const daily = 'daily';
  static const weekly = 'weekly';
  static const monthly = 'monthly';
}

/// Whether routine [r] has an occurrence on [day] (ignoring its start/end
/// dates and status; callers check those).
///
/// - daily:  every `repeatInterval` days counted from `startDate`.
/// - weekly: on the `weekdays` mask, in every `repeatInterval`-th week,
///   counting weeks (Monday-based) from the week containing `startDate`.
/// - monthly: on `monthDay` (or the month's last day when shorter), in
///   every `repeatInterval`-th month counted from `startDate`'s month.
bool occursOn(RecurrenceRow r, DateTime day) {
  final interval = r.repeatInterval < 1 ? 1 : r.repeatInterval;
  final start = parseDateKey(r.startDate);
  final d = DateTime(day.year, day.month, day.day);
  final days = _daysBetween(start, d);
  if (days < 0) return false;

  if (r.frequency == Frequency.daily) return days % interval == 0;

  if (r.frequency == Frequency.monthly) {
    final months = (d.year - start.year) * 12 + d.month - start.month;
    if (months % interval != 0) return false;
    final wanted = (r.monthDay ?? start.day).clamp(1, 31);
    return d.day == (wanted < daysInMonth(d) ? wanted : daysInMonth(d));
  }

  if (!Weekdays.includes(r.weekdays, d)) return false;
  if (interval == 1) return true;
  final startMonday = start.subtract(Duration(days: start.weekday - 1));
  final weeks = _daysBetween(startMonday, d) ~/ 7;
  return weeks % interval == 0;
}

int daysInMonth(DateTime d) => DateTime.utc(d.year, d.month + 1, 0).day;

/// "1st", "2nd", "23rd", "31st".
String ordinal(int n) {
  if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
  return switch (n % 10) { 1 => '${n}st', 2 => '${n}nd', 3 => '${n}rd', _ => '${n}th' };
}

/// Calendar-day difference that is immune to DST shifts.
int _daysBetween(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

/// "Every day", "Every 3 days", "Weekdays", "Every 2 weeks on Mon, Thu",
/// "Monthly on the 15th", "Every 3 months on the last day".
String describeRepeat(RecurrenceRow r) =>
    describeRepeatParts(r.frequency, r.repeatInterval, r.weekdays, monthDay: r.monthDay);

String describeRepeatParts(String frequency, int interval, int weekdays, {int? monthDay}) {
  if (frequency == Frequency.monthly) {
    final day = monthDay == 31 ? 'the last day' : 'the ${ordinal(monthDay ?? 1)}';
    return interval <= 1 ? 'Monthly on $day' : 'Every $interval months on $day';
  }
  if (frequency == Frequency.daily) {
    return interval <= 1 ? 'Every day' : 'Every $interval days';
  }
  final days = Weekdays.describe(weekdays);
  if (interval <= 1) {
    if (weekdays == Weekdays.everyDay) return 'Every day';
    if (weekdays == Weekdays.workdays || weekdays == Weekdays.weekend) return days;
    return 'Every $days';
  }
  final on = weekdays == Weekdays.everyDay ? 'every day' : 'on $days';
  return 'Every $interval weeks $on';
}
