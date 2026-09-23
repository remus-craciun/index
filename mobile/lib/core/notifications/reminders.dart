import '../db/app_database.dart';
import '../time.dart';

/// A notification to schedule for a task reminder.
class PlannedReminder {
  const PlannedReminder({required this.id, required this.taskId, required this.at, required this.title, required this.body});

  final int id;
  final String taskId;
  final DateTime at;
  final String title;
  final String body;
}

/// Reminder choices offered in the UI, in minutes before the start.
const reminderOptions = <int, String>{
  0: 'At start',
  5: '5 min before',
  15: '15 min before',
  30: '30 min before',
  60: '1 hour before',
  1440: '1 day before',
};

String describeReminder(int minutes) => reminderOptions[minutes] ?? '$minutes min before';

/// Works out when each task's reminder fires: [TaskRow.reminderMinutes]
/// before its start time, or before [defaultTime] (HH:MM) on its date when
/// it has no start time. Past reminders are dropped; the soonest [limit]
/// are returned (Android caps scheduled alarms per app).
List<PlannedReminder> planReminders(
  Iterable<TaskRow> tasks, {
  required DateTime now,
  String defaultTime = '09:00',
  int limit = 60,
}) {
  final out = <PlannedReminder>[];
  for (final t in tasks) {
    if (t.reminderMinutes == null || t.scheduledDate == null || t.deletedAt != null || t.status != 'pending') {
      continue;
    }
    final start = _at(t.scheduledDate!, t.startTime ?? defaultTime);
    final at = start.subtract(Duration(minutes: t.reminderMinutes!));
    if (!at.isAfter(now)) continue;

    final when = t.startTime == null
        ? (t.scheduledDate == dateKey(now) ? 'today' : 'on ${t.scheduledDate}')
        : (t.endTime == null ? 'at ${t.startTime}' : '${t.startTime}–${t.endTime}');
    out.add(PlannedReminder(
      id: notificationId(t.id),
      taskId: t.id,
      at: at,
      title: t.title,
      body: t.reminderMinutes == 0 ? 'Starting now' : 'Coming up $when',
    ));
  }
  out.sort((a, b) => a.at.compareTo(b.at));
  return out.take(limit).toList();
}

/// Stable 31-bit notification ID for a task (FNV-1a over the UUID).
int notificationId(String taskId) {
  var h = 0x811c9dc5;
  for (final c in taskId.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xffffffff;
  }
  return h & 0x7fffffff;
}

DateTime _at(String date, String hhmm) {
  final d = parseDateKey(date);
  return DateTime(d.year, d.month, d.day, int.parse(hhmm.substring(0, 2)), int.parse(hhmm.substring(3, 5)));
}
