import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:index_app/core/db/app_database.dart';
import 'package:index_app/core/sync/sync_engine.dart';
import 'package:index_app/core/time.dart';
import 'package:index_app/features/routines/data/routines_repository.dart';
import 'package:index_app/features/routines/domain/weekdays.dart';
import 'package:index_app/features/tasks/data/tasks_repository.dart';

import '../support.dart';

void main() {
  late AppDatabase db;
  late RoutinesRepository routines;
  late TasksRepository tasks;
  // A Monday, so weekday arithmetic in the tests is easy to follow.
  final monday = DateTime(2026, 3, 2);

  setUp(() {
    db = memoryDb();
    routines = RoutinesRepository(db, onChanged: () {}, clock: () => monday);
    tasks = TasksRepository(db, onChanged: () {});
  });
  tearDown(() => db.close());

  Future<List<TaskRow>> occurrences(String routineId, {bool includeDeleted = false}) =>
      (db.select(db.tasks)
            ..where((t) => t.recurrenceId.equals(routineId) & (includeDeleted ? const Constant(true) : t.deletedAt.isNull()))
            ..orderBy([(t) => OrderingTerm(expression: t.scheduledDate)]))
          .get();

  Future<String> work() async {
    final id = await routines.createRoutine(
      title: 'Work',
      weekdays: Weekdays.workdays,
      startTime: '08:00',
      endTime: '17:00',
      reminderMinutes: 15,
      startDate: dateKey(monday),
    );
    await routines.generate(today: monday);
    return id;
  }

  test('generates weekday occurrences with the time window, clean and deterministic', () async {
    final id = await work();
    final occ = await occurrences(id);

    // 61 days from Monday 2 March: 9 full weeks (45 workdays) + Mon 4 May = 44..45.
    expect(occ, isNotEmpty);
    expect(occ.every((t) => Weekdays.includes(Weekdays.workdays, parseDateKey(t.scheduledDate!))), isTrue);
    expect(occ.first.scheduledDate, '2026-03-02');
    expect(occ.first.startTime, '08:00');
    expect(occ.first.endTime, '17:00');
    expect(occ.first.estimatedMinutes, 540);
    expect(occ.first.reminderMinutes, 15);
    expect(occ.first.id, RoutinesRepository.occurrenceId(id, '2026-03-02'));
    expect(occ.every((t) => !t.dirty), isTrue, reason: 'untouched occurrences are not pushed');
    expect(occ.last.scheduledDate!.compareTo(dateKey(monday.add(const Duration(days: 60)))), lessThanOrEqualTo(0));

    // Idempotent.
    final count = occ.length;
    await routines.generate(today: monday);
    expect(await occurrences(id), hasLength(count));
  });

  test('another device generates identical rows', () async {
    final id = await work();
    final other = memoryDb();
    addTearDown(other.close);
    final routine = await routines.getRoutine(id);
    await other.into(other.recurrences).insert(routine!.copyWith(dirty: false));
    await RoutinesRepository(other, onChanged: () {}, clock: () => monday).generate();

    final mine = await occurrences(id);
    final theirs = await (other.select(other.tasks)..orderBy([(t) => OrderingTerm(expression: t.scheduledDate)])).get();
    expect(theirs.map((t) => t.id), mine.map((t) => t.id));
    expect(theirs.map((t) => t.updatedAt), mine.map((t) => t.updatedAt));
  });

  test('editing the routine updates untouched future occurrences only', () async {
    final id = await work();
    final tuesday = (await occurrences(id))[1];
    await tasks.updateTask(tuesday, notes: 'bring laptop'); // individually edited
    await tasks.toggleCompleted((await occurrences(id)).first); // Monday done

    final r = (await routines.getRoutine(id))!;
    await routines.updateRoutine(r.copyWith(title: 'Office', weekdays: Weekdays.bit(1) | Weekdays.bit(2) | Weekdays.bit(3)));
    await routines.generate(today: monday);

    final occ = await occurrences(id);
    final byDate = {for (final t in occ) t.scheduledDate: t};
    expect(byDate['2026-03-02']!.title, 'Work', reason: 'completed occurrence untouched');
    expect(byDate['2026-03-03']!.title, 'Work', reason: 'individually edited occurrence kept');
    expect(byDate['2026-03-04']!.title, 'Office');
    expect(byDate.containsKey('2026-03-05'), isFalse, reason: 'Thursday removed');
    expect(byDate.containsKey('2026-03-06'), isFalse, reason: 'Friday removed');

    // Adding Thursday back brings its occurrences back.
    final r2 = (await routines.getRoutine(id))!;
    await routines.updateRoutine(r2.copyWith(weekdays: r2.weekdays | Weekdays.bit(4)));
    await routines.generate(today: monday);
    expect((await occurrences(id)).map((t) => t.scheduledDate), contains('2026-03-05'));
  });

  test('a deleted occurrence is not regenerated, even after sync purges tombstones', () async {
    final server = FakeSyncServer();
    final id = await work();
    final wednesday = (await occurrences(id))[2];
    await tasks.deleteTask(wednesday);
    await SyncEngine(db, server.handle).run();
    await routines.generate(today: monday);

    expect((await occurrences(id)).map((t) => t.scheduledDate), isNot(contains(wednesday.scheduledDate)));
    expect(server.row('tasks', wednesday.id)!['deleted_at'], isNotNull);
    expect(server.row('recurrences', id), isNotNull, reason: 'routine pushed before its occurrence');
    // Untouched occurrences were never pushed.
    final pushedTasks = server.requests.expand((r) => r['changes']['tasks'] as List).toList();
    expect(pushedTasks, hasLength(1));
  });

  test('pausing and deleting remove future untouched occurrences', () async {
    final id = await work();
    await tasks.toggleCompleted((await occurrences(id)).first);
    await routines.setPaused((await routines.getRoutine(id))!, true);
    await routines.generate(today: monday);
    expect((await occurrences(id)).map((t) => t.scheduledDate), ['2026-03-02']);

    await routines.setPaused((await routines.getRoutine(id))!, false);
    await routines.generate(today: monday);
    expect((await occurrences(id)).length, greaterThan(1));

    await routines.deleteRoutine((await routines.getRoutine(id))!);
    await routines.generate(today: monday);
    expect((await occurrences(id)).map((t) => t.scheduledDate), ['2026-03-02'], reason: 'history kept');
  });

  test('a routine deleted on another device cleans up after sync', () async {
    final server = FakeSyncServer();
    final id = await work();
    await SyncEngine(db, server.handle).run();
    final tuesday = (await occurrences(id))[1].scheduledDate;

    // The other device deletes the routine; the tombstone arrives via sync.
    final row = server.row('recurrences', id)!;
    server.put('recurrences', {...row, 'deleted_at': '2999-01-01T00:00:00.000Z', 'updated_at': '2999-01-01T00:00:00.000Z'});
    await SyncEngine(db, server.handle).run();
    await routines.generate(today: monday);

    expect((await occurrences(id)).map((t) => t.scheduledDate), isNot(contains(tuesday)));
    expect((await routines.getRoutine(id))!.deletedAt, isNotNull, reason: 'routine tombstone kept locally');
  });

  test('generates every N days and every N weeks', () async {
    final plants = await routines.createRoutine(
        title: 'Water plants', frequency: 'daily', repeatInterval: 3, weekdays: 127, startDate: '2026-03-02');
    final review = await routines.createRoutine(
        title: 'Review', repeatInterval: 2, weekdays: Weekdays.bit(DateTime.friday), startDate: '2026-03-02');
    await routines.generate(today: monday);

    final p = (await occurrences(plants)).map((t) => t.scheduledDate).take(4).toList();
    expect(p, ['2026-03-02', '2026-03-05', '2026-03-08', '2026-03-11']);
    final r = (await occurrences(review)).map((t) => t.scheduledDate).take(3).toList();
    expect(r, ['2026-03-06', '2026-03-20', '2026-04-03']);

    // Switching Review to every week fills in the skipped Fridays.
    final row = (await routines.getRoutine(review))!;
    await routines.updateRoutine(row.copyWith(repeatInterval: 1));
    await routines.generate(today: monday);
    expect((await occurrences(review)).map((t) => t.scheduledDate).take(3), ['2026-03-06', '2026-03-13', '2026-03-20']);
  });

  test('generates monthly occurrences', () async {
    final bills = await routines.createRoutine(
        title: 'Pay bills', frequency: 'monthly', monthDay: 31, weekdays: 127, startDate: '2026-03-02');
    await routines.generate(today: monday);
    // 60-day window from 2 March covers 31 March and 30 April.
    expect((await occurrences(bills)).map((t) => t.scheduledDate), ['2026-03-31', '2026-04-30']);
    expect((await routines.getRoutine(bills))!.monthDay, 31);

    // Default day of month is the start date's day.
    final gym = await routines.createRoutine(title: 'Check-in', frequency: 'monthly', weekdays: 127, startDate: '2026-03-10');
    expect((await routines.getRoutine(gym))!.monthDay, 10);
  });

  test('end date limits generation', () async {
    final id = await routines.createRoutine(
        title: 'Sprint', weekdays: Weekdays.everyDay, startDate: '2026-03-02', endDate: '2026-03-04');
    await routines.generate(today: monday);
    expect((await occurrences(id)).map((t) => t.scheduledDate), ['2026-03-02', '2026-03-03', '2026-03-04']);
  });

  test('Today shows only the current occurrence; inbox hides routines', () async {
    final walkRepo = RoutinesRepository(db, onChanged: () {}, clock: () => DateTime(2026, 3, 1));
    final id = await walkRepo.createRoutine(title: 'Walk', weekdays: Weekdays.everyDay, startDate: '2026-03-01');
    await tasks.addTask(title: 'Chore', scheduledDate: '2026-03-01');

    final today = await tasks.watchToday('2026-03-02').first;
    expect(today.map((e) => e.task.title), ['Chore', 'Walk'], reason: 'yesterday\'s Walk is not overdue');
    expect(today.last.task.recurrenceId, id);
    final inbox = await tasks.watchInbox().first;
    expect(inbox.map((t) => t.title), ['Chore']);
  });
}
