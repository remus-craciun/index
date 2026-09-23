import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:index_app/core/db/app_database.dart';
import 'package:index_app/core/sync/sync_engine.dart';
import 'package:index_app/features/plans/data/plans_repository.dart';
import 'package:index_app/features/tasks/data/tasks_repository.dart';

import '../support.dart';

void main() {
  late AppDatabase db;
  late FakeSyncServer server;
  late TasksRepository tasks;
  late PlansRepository plans;

  setUp(() {
    db = memoryDb();
    server = FakeSyncServer();
    tasks = TasksRepository(db, onChanged: () {});
    plans = PlansRepository(db, onChanged: () {});
  });
  tearDown(() => db.close());

  Future<TaskRow?> task(String id) => (db.select(db.tasks)..where((t) => t.id.equals(id))).getSingleOrNull();

  test('pushes dirty rows parents-first and marks them clean', () async {
    final planId = await plans.createPlan(title: 'Go');
    await plans.addMilestone(planId, 'Basics');
    final ms = await db.select(db.milestones).getSingle();
    final taskId = await tasks.addTask(title: 'Read', milestoneId: ms.id);

    final result = await SyncEngine(db, server.handle).run();

    expect(result.pushed, 3);
    expect(result.moreDirty, isFalse);
    final body = server.requests.single;
    expect(body['cursor'], 0);
    expect((body['changes']['learning_plans'] as List).single['id'], planId);
    expect(server.row('tasks', taskId)!['milestone_id'], ms.id);
    expect((await task(taskId))!.dirty, isFalse);
    expect(await db.getValue(SyncEngine.cursorKey), '${server.rev}');
  });

  test('pulls remote rows and advances the cursor', () async {
    server.put('tasks', {
      'id': 't1', 'milestone_id': null, 'title': 'From phone', 'notes': '', 'scheduled_date': '2026-01-01',
      'estimated_minutes': 10, 'status': 'pending', 'created_at': '2026-01-01T00:00:00.000Z',
      'updated_at': '2026-01-01T00:00:00.000Z', 'deleted_at': null,
    });
    await SyncEngine(db, server.handle).run();
    expect((await task('t1'))!.title, 'From phone');

    // Second sync sends the cursor and receives nothing new.
    final r = await SyncEngine(db, server.handle).run();
    expect(server.requests.last['cursor'], server.rev);
    expect(r.pulled, 0);
  });

  test('newer remote edit replaces an older local one', () async {
    final id = await tasks.addTask(title: 'mine');
    await SyncEngine(db, server.handle).run();
    final row = server.row('tasks', id)!;
    server.put('tasks', {...row, 'title': 'theirs', 'updated_at': '2999-01-01T00:00:00.000Z'});

    final local = (await task(id))!;
    await tasks.updateTask(local, title: 'mine v2'); // older than 2999
    await SyncEngine(db, server.handle).run();

    final after = (await task(id))!;
    expect(after.title, 'theirs');
    expect(after.dirty, isFalse);
  });

  test('local edit made during a sync stays dirty', () async {
    final id = await tasks.addTask(title: 'v1');
    await SyncEngine(db, (body) async {
      final resp = await server.handle(body);
      // User edits while the request is in flight.
      await tasks.updateTask((await task(id))!, title: 'v2');
      return resp;
    }).run().then((r) => expect(r.moreDirty, isTrue));

    final row = (await task(id))!;
    expect(row.title, 'v2');
    expect(row.dirty, isTrue);
  });

  test('tombstones are pushed, then purged locally', () async {
    final id = await tasks.addTask(title: 'gone soon');
    await SyncEngine(db, server.handle).run();
    await tasks.deleteTask((await task(id))!);
    await SyncEngine(db, server.handle).run();

    expect(server.row('tasks', id)!['deleted_at'], isNotNull);
    expect(await task(id), isNull);
  });

  test('reset replaces clean rows but keeps unsynced edits', () async {
    final keep = await tasks.addTask(title: 'unsynced');
    await db.into(db.tasks).insert(TasksCompanion.insert(
          id: 'stale', title: 'stale', createdAt: 'x', updatedAt: 'x', dirty: const Value(false)));

    await SyncEngine(db, (body) async => {
          'cursor': 1,
          'reset': true,
          'changes': {'learning_plans': [], 'milestones': [], 'tasks': []},
        }).run();

    expect(await task('stale'), isNull);
    expect((await task(keep))!.dirty, isTrue);
  });

  test('deleting a plan cascades to milestones and tasks', () async {
    final planId = await plans.createPlan(title: 'P');
    await plans.addMilestone(planId, 'M');
    final ms = await db.select(db.milestones).getSingle();
    final t = await tasks.addTask(title: 'T', milestoneId: ms.id);
    await plans.deletePlan((await db.select(db.learningPlans).getSingle()));

    expect((await task(t))!.deletedAt, isNotNull);
    expect((await db.select(db.milestones).getSingle()).deletedAt, isNotNull);
  });

  test('restore after delete survives a sync in between', () async {
    final id = await tasks.addTask(title: 'oops');
    await SyncEngine(db, server.handle).run();
    final tomb = await tasks.deleteTask((await task(id))!);
    await SyncEngine(db, server.handle).run();
    expect(await task(id), isNull);

    await tasks.restoreTask(tomb);
    await SyncEngine(db, server.handle).run();
    expect(server.row('tasks', id)!['deleted_at'], isNull);
    expect((await task(id))!.deletedAt, isNull);
  });
}
