// End-to-end check of the mobile data layer against a real server.
//
//   cd server && DB_PATH=/tmp/e2e.db PORT=18090 go run .
//   cd mobile && INDEX_E2E_URL=http://localhost:18090 flutter test test/e2e
//
// Skipped unless INDEX_E2E_URL is set. Expects a fresh server (no account).
@Tags(['e2e'])
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:index_app/core/db/app_database.dart';
import 'package:index_app/core/network/api.dart';
import 'package:index_app/core/network/api_exception.dart';
import 'package:index_app/core/network/token_store.dart';
import 'package:index_app/core/sync/sync_engine.dart';
import 'package:index_app/core/time.dart';
import 'package:index_app/features/plans/data/plans_repository.dart';
import 'package:index_app/features/routines/data/routines_repository.dart';
import 'package:index_app/features/routines/domain/weekdays.dart';
import 'package:index_app/features/tasks/data/tasks_repository.dart';

import '../support.dart';

class Device {
  Device(this.api) : db = memoryDb() {
    tasks = TasksRepository(db, onChanged: () {});
    plans = PlansRepository(db, onChanged: () {});
    routines = RoutinesRepository(db, onChanged: () {});
  }

  final Api api;
  final AppDatabase db;
  late final TasksRepository tasks;
  late final PlansRepository plans;
  late final RoutinesRepository routines;

  Future<SyncResult> sync() => SyncEngine(db, api.sync).run();

  Future<TaskRow?> task(String id) =>
      (db.select(db.tasks)..where((t) => t.id.equals(id))).getSingleOrNull();
}

void main() {
  final url = Platform.environment['INDEX_E2E_URL'];

  test('two devices stay in sync through the real server', () async {
    final public = PublicApi();
    await public.health(url!);
    expect(await public.hasUser(url), isFalse, reason: 'use a fresh server');

    final tokens = await public.register(url, 'e2e@example.com', 'correct horse');
    expect(await public.hasUser(url), isTrue);
    await expectLater(
      public.register(url, 'other@example.com', 'correct horse'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'registration_disabled')),
    );

    Device device(TokenStore store) => Device(Api.create(
          serverUrl: url,
          tokens: store,
          publicApi: public,
          onSessionExpired: () => fail('session expired unexpectedly'),
        ));

    final storeA = MemoryTokenStore()..write(tokens);
    // Device B starts with a bogus access token: the interceptor must
    // refresh it transparently using the refresh token.
    final storeB = MemoryTokenStore()
      ..write(AuthTokens(accessToken: 'expired', refreshToken: tokens.refreshToken));
    final a = device(storeA);
    final b = device(storeB);
    addTearDown(() async {
      await a.db.close();
      await b.db.close();
    });

    // A creates a plan with a task, plus an ad-hoc task, all offline.
    final planId = await a.plans.createPlan(title: 'Distributed Go', targetDate: '2026-12-01');
    await a.plans.addMilestone(planId, 'Foundations');
    final ms = await a.db.select(a.db.milestones).getSingle();
    final learnId = await a.tasks.addTask(title: 'Goroutines', milestoneId: ms.id, scheduledDate: '2026-10-01', estimatedMinutes: 30);
    final choreId = await a.tasks.addTask(title: 'Buy milk', scheduledDate: '2026-10-01');
    expect((await a.sync()).pushed, 4);

    // B pulls everything.
    await b.sync();
    expect((await storeB.read())!.accessToken, isNot('expired'), reason: 'token was refreshed');
    expect((await b.task(learnId))!.milestoneId, ms.id);
    final bToday = await b.tasks.watchToday('2026-10-01').first;
    expect(bToday.map((e) => e.task.title), ['Goroutines', 'Buy milk']);
    expect(bToday.first.planTitle, 'Distributed Go');

    // B completes the learning task and deletes the chore; A sees both.
    await b.tasks.toggleCompleted((await b.task(learnId))!);
    await b.tasks.deleteTask((await b.task(choreId))!);
    await b.sync();
    await a.sync();
    expect((await a.task(learnId))!.status, 'completed');
    expect(await a.task(choreId), isNull, reason: 'tombstone pulled and purged');

    // Concurrent edits: the later edit wins on both devices.
    await a.tasks.updateTask((await a.task(learnId))!, title: 'from A');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await b.tasks.updateTask((await b.task(learnId))!, title: 'from B');
    await a.sync();
    await b.sync();
    await a.sync();
    expect((await a.task(learnId))!.title, 'from B');
    expect((await b.task(learnId))!.title, 'from B');
    expect((await a.task(learnId))!.dirty, isFalse);

    // Applying a plan revision (as after an AI preview) reaches B via sync.
    // The learning task is completed, so the revision can't drop it.
    await a.api.applyRevision(planId: planId, minutesPerDay: 60, startDate: todayKey(), revision: {
      'title': 'Distributed Go v2',
      'description': '',
      'milestones': [
        {
          'id': ms.id,
          'title': 'Basics',
          'order_index': 1,
          'tasks': [
            {'title': 'Channels', 'estimated_minutes': 30, 'notes': ''},
          ],
        },
      ],
    });
    await b.sync();
    expect((await b.db.select(b.db.learningPlans).getSingle()).title, 'Distributed Go v2');
    expect((await b.db.select(b.db.milestones).getSingle()).title, 'Basics');
    final bPlanTasks = await (b.db.select(b.db.tasks)..where((t) => t.milestoneId.equals(ms.id))).get();
    expect(bPlanTasks.map((t) => t.title).toSet(), {'from B', 'Channels'});
    await a.sync();

    // Deleting the plan on A cascades on B.
    await a.plans.deletePlan(await a.db.select(a.db.learningPlans).getSingle());
    await a.sync();
    await b.sync();
    expect(await b.db.select(b.db.learningPlans).get(), isEmpty);
    expect(await b.task(learnId), isNull);

    // Routines: A creates one and completes today's occurrence; B gets the
    // routine, generates the same occurrences and sees today's as done.
    final routineId = await a.routines.createRoutine(
        title: 'Work', weekdays: Weekdays.everyDay, startTime: '08:00', endTime: '17:00', reminderMinutes: 15);
    final today = todayKey();
    final occId = RoutinesRepository.occurrenceId(routineId, today);
    await a.tasks.toggleCompleted((await a.task(occId))!);
    await a.sync();
    await b.sync();
    await b.routines.generate();
    final bOcc = (await b.task(occId))!;
    expect(bOcc.status, 'completed');
    expect(bOcc.completedAt, isNotNull);
    expect(bOcc.startTime, '08:00');
    final tomorrowId = RoutinesRepository.occurrenceId(routineId, dateKey(DateTime.now().add(const Duration(days: 1))));
    expect((await b.task(tomorrowId))!.createdAt, (await a.task(tomorrowId))!.createdAt, reason: 'identical generation');

    // Deleting the routine on B removes upcoming occurrences on A, keeps history.
    await b.routines.deleteRoutine((await b.routines.getRoutine(routineId))!);
    await b.sync();
    await a.sync();
    await a.routines.generate();
    expect(await a.task(tomorrowId), isNull);
    expect((await a.task(occId))!.status, 'completed');

    // AI endpoints surface a clear error when the server has no key.
    try {
      await a.api.decomposePlan(prompt: 'Learn Go', startDate: '2026-10-01', minutesPerDay: 60);
    } on ApiException catch (e) {
      expect(e.code, anyOf('ai_disabled', 'ai_unavailable'));
    }
  }, skip: url == null ? 'set INDEX_E2E_URL to run' : false);

  test('local writes survive with no server', () async {
    final d = Device(Api.withDio(Dio()));
    addTearDown(d.db.close);
    await d.tasks.addTask(title: 'offline');
    expect(await (d.db.select(d.db.tasks)..where((t) => t.dirty.equals(true))).get(), hasLength(1));
  }, skip: url == null ? 'set INDEX_E2E_URL to run' : false);
}
