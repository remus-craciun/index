import 'package:flutter_test/flutter_test.dart';
import 'package:index_app/core/db/app_database.dart';
import 'package:index_app/core/notifications/reminders.dart';
import 'package:index_app/features/tasks/data/tasks_repository.dart';

import '../support.dart';

TaskRow task(String id, {String? date, String? start, int? reminder, String status = 'pending'}) => TaskRow(
      id: id,
      title: id,
      notes: '',
      scheduledDate: date,
      startTime: start,
      reminderMinutes: reminder,
      status: status,
      createdAt: 'x',
      updatedAt: 'x',
      dirty: false,
    );

void main() {
  final now = DateTime(2026, 3, 2, 10, 0);

  test('plans reminders relative to the start or the default time', () {
    final planned = planReminders([
      task('standup', date: '2026-03-02', start: '10:30', reminder: 15),
      task('untimed-tomorrow', date: '2026-03-03', reminder: 60),
      task('day-before', date: '2026-03-04', start: '08:00', reminder: 1440),
      task('past', date: '2026-03-02', start: '09:00', reminder: 0),
      task('no-reminder', date: '2026-03-02', start: '11:00'),
      task('done', date: '2026-03-02', start: '12:00', reminder: 5, status: 'completed'),
    ], now: now, defaultTime: '09:00');

    expect(planned.map((r) => r.taskId), ['standup', 'untimed-tomorrow', 'day-before']);
    expect(planned[0].at, DateTime(2026, 3, 2, 10, 15));
    expect(planned[0].body, 'Coming up at 10:30');
    expect(planned[1].at, DateTime(2026, 3, 3, 8, 0));
    expect(planned[2].at, DateTime(2026, 3, 3, 8, 0));
  });

  test('caps the number of reminders and keeps IDs stable', () {
    final many = [for (var i = 0; i < 100; i++) task('t$i', date: '2026-03-05', start: '09:00', reminder: 0)];
    expect(planReminders(many, now: now, limit: 60), hasLength(60));
    expect(notificationId('abc'), notificationId('abc'));
    expect(notificationId('abc'), isNot(notificationId('abd')));
    expect(notificationId('0192f7a0-0000-7000-8000-000000000000'), inInclusiveRange(0, 0x7fffffff));
  });

  test('completing sets completed_at, reopening clears it', () async {
    final db = memoryDb();
    addTearDown(db.close);
    final repo = TasksRepository(db, onChanged: () {});
    final id = await repo.addTask(title: 'x');
    await repo.toggleCompleted((await repo.getTask(id))!);
    final done = (await repo.getTask(id))!;
    expect(done.completedAt, isNotNull);
    expect((await repo.watchCompleted().first).single.task.id, id);

    await repo.toggleCompleted(done);
    expect((await repo.getTask(id))!.completedAt, isNull);
    expect(await repo.watchCompleted().first, isEmpty);
  });
}
