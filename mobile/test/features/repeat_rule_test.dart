import 'package:flutter_test/flutter_test.dart';
import 'package:index_app/core/db/app_database.dart';
import 'package:index_app/core/time.dart';
import 'package:index_app/features/routines/domain/repeat_rule.dart';
import 'package:index_app/features/routines/domain/weekdays.dart';

RecurrenceRow rule({
  String frequency = 'weekly',
  int interval = 1,
  int weekdays = 127,
  int? monthDay,
  String start = '2026-03-04',
}) =>
    RecurrenceRow(
      id: 'r',
      title: 'r',
      notes: '',
      frequency: frequency,
      repeatInterval: interval,
      weekdays: weekdays,
      monthDay: monthDay,
      startDate: start,
      status: 'active',
      createdAt: 'x',
      updatedAt: 'x',
      dirty: false,
    );

List<String> matches(RecurrenceRow r, String from, int days) {
  final start = parseDateKey(from);
  return [
    for (var i = 0; i < days; i++)
      if (occursOn(r, DateTime(start.year, start.month, start.day + i))) dateKey(DateTime(start.year, start.month, start.day + i)),
  ];
}

void main() {
  test('every 3 days counts from the start date', () {
    // Start Wed 4 March 2026.
    expect(matches(rule(frequency: 'daily', interval: 3), '2026-03-01', 12),
        ['2026-03-04', '2026-03-07', '2026-03-10']);
  });

  test('every day and weekly on one weekday', () {
    expect(matches(rule(frequency: 'daily'), '2026-03-03', 3), ['2026-03-04', '2026-03-05']);
    expect(matches(rule(weekdays: Weekdays.bit(DateTime.friday)), '2026-03-01', 21),
        ['2026-03-06', '2026-03-13', '2026-03-20']);
  });

  test('every 2 weeks on Mon and Thu counts weeks from the start week', () {
    // Start is Wednesday 4 March: that week's Monday (2 March) is before the
    // start, its Thursday (5 March) counts; the next week is skipped.
    final r = rule(interval: 2, weekdays: Weekdays.bit(DateTime.monday) | Weekdays.bit(DateTime.thursday));
    expect(matches(r, '2026-03-01', 35), ['2026-03-05', '2026-03-16', '2026-03-19', '2026-03-30', '2026-04-02']);
  });

  test('interval arithmetic survives daylight saving changes', () {
    // Europe switches to summer time on 29 March 2026; counting must not drift.
    final r = rule(frequency: 'daily', interval: 7, start: '2026-03-01');
    expect(matches(r, '2026-03-25', 14), ['2026-03-29', '2026-04-05']);
  });

  test('monthly on a day, clamped to short months', () {
    final rent = rule(frequency: 'monthly', monthDay: 31, start: '2026-01-01');
    final hits = matches(rent, '2026-01-01', 400);
    expect(hits.take(6), ['2026-01-31', '2026-02-28', '2026-03-31', '2026-04-30', '2026-05-31', '2026-06-30']);
    // 2028 is a leap year.
    expect(matches(rent, '2028-02-01', 29), ['2028-02-29']);

    final fifteenth = rule(frequency: 'monthly', monthDay: 15, start: '2026-03-20');
    expect(matches(fifteenth, '2026-03-01', 80), ['2026-04-15', '2026-05-15'], reason: 'March 15 is before the start');
  });

  test('every N months counts from the start month', () {
    final quarterly = rule(frequency: 'monthly', interval: 3, monthDay: 1, start: '2026-02-10');
    expect(matches(quarterly, '2026-02-01', 370), ['2026-05-01', '2026-08-01', '2026-11-01', '2027-02-01']);
  });

  test('descriptions', () {
    expect(describeRepeatParts('monthly', 1, 127, monthDay: 15), 'Monthly on the 15th');
    expect(describeRepeatParts('monthly', 1, 127, monthDay: 2), 'Monthly on the 2nd');
    expect(describeRepeatParts('monthly', 3, 127, monthDay: 31), 'Every 3 months on the last day');
    expect(ordinal(11), '11th');
    expect(ordinal(22), '22nd');
    expect(describeRepeatParts('daily', 1, 127), 'Every day');
    expect(describeRepeatParts('daily', 3, 127), 'Every 3 days');
    expect(describeRepeatParts('weekly', 1, Weekdays.workdays), 'Weekdays');
    expect(describeRepeatParts('weekly', 1, Weekdays.bit(1)), 'Every Mon');
    expect(describeRepeatParts('weekly', 2, Weekdays.bit(1) | Weekdays.bit(4)), 'Every 2 weeks on Mon, Thu');
    expect(describeRepeatParts('weekly', 3, 127), 'Every 3 weeks every day');
  });
}
