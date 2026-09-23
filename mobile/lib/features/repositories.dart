import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:drift/drift.dart' show TableUpdateQuery;

import '../core/db/app_database.dart';
import '../core/notifications/notification_service.dart';
import '../core/notifications/reminders.dart';
import '../core/providers.dart';
import '../core/sync/sync_controller.dart';
import '../core/time.dart';
import 'ai/data/ai_repository.dart';
import 'plans/data/plans_repository.dart';
import 'plans/domain/plan_models.dart';
import 'routines/data/routines_repository.dart';
import 'tasks/data/tasks_repository.dart';
import 'tasks/domain/today_entry.dart';

part 'repositories.g.dart';

@Riverpod(keepAlive: true)
TasksRepository tasksRepository(Ref ref) => TasksRepository(
      ref.watch(appDatabaseProvider),
      onChanged: () => ref.read(syncControllerProvider.notifier).requestSync(),
    );

@Riverpod(keepAlive: true)
PlansRepository plansRepository(Ref ref) => PlansRepository(
      ref.watch(appDatabaseProvider),
      onChanged: () => ref.read(syncControllerProvider.notifier).requestSync(),
    );

/// Kept alive: AI calls take up to a minute, and the repository calls back
/// into the sync controller afterwards. An auto-disposed provider would be
/// gone by then ("Cannot use the Ref ... after it has been disposed").
@Riverpod(keepAlive: true)
AiRepository aiRepository(Ref ref) => AiRepository(
      db: ref.watch(appDatabaseProvider),
      api: ref.watch(apiProvider),
      syncNow: () => ref.read(syncControllerProvider.notifier).syncNow(),
      requestSync: () => ref.read(syncControllerProvider.notifier).requestSync(),
    );

/// The current local date; updates at midnight so Today rolls over.
@Riverpod(keepAlive: true)
class CurrentDay extends _$CurrentDay {
  @override
  String build() {
    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    final timer = Timer(nextMidnight.difference(now) + const Duration(seconds: 1), ref.invalidateSelf);
    ref.onDispose(timer.cancel);
    return dateKey(now);
  }

  void refresh() {
    if (state != todayKey()) ref.invalidateSelf();
  }
}

@riverpod
Stream<List<TodayEntry>> todayEntries(Ref ref) {
  final day = ref.watch(currentDayProvider);
  return ref.watch(tasksRepositoryProvider).watchToday(day);
}

@riverpod
Stream<List<TaskRow>> inboxTasks(Ref ref) => ref.watch(tasksRepositoryProvider).watchInbox();

@riverpod
Stream<List<PlanSummary>> planSummaries(Ref ref) => ref.watch(plansRepositoryProvider).watchPlans();

@riverpod
Stream<PlanDetail?> planDetail(Ref ref, String id) => ref.watch(plansRepositoryProvider).watchPlan(id);

@Riverpod(keepAlive: true)
RoutinesRepository routinesRepository(Ref ref) => RoutinesRepository(
      ref.watch(appDatabaseProvider),
      onChanged: () => ref.read(syncControllerProvider.notifier).requestSync(),
    );

@riverpod
Stream<List<RecurrenceRow>> routines(Ref ref) => ref.watch(routinesRepositoryProvider).watchRoutines();

@riverpod
Stream<RecurrenceRow?> routine(Ref ref, String id) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.recurrences)..where((r) => r.id.equals(id))).watchSingleOrNull();
}

/// Keeps routine occurrences generated: at startup, whenever routines
/// change (locally or via sync) and when the day rolls over.
@Riverpod(keepAlive: true)
void routineGenerator(Ref ref) {
  ref.watch(currentDayProvider);
  final db = ref.watch(appDatabaseProvider);
  final repo = ref.watch(routinesRepositoryProvider);
  Timer? debounce;
  void run() {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 300), () => repo.generate());
  }

  final sub = db.tableUpdates(TableUpdateQuery.onTable(db.recurrences)).listen((_) => run());
  ref.onDispose(() {
    sub.cancel();
    debounce?.cancel();
  });
  Future.microtask(repo.generate);
}

@riverpod
Stream<List<TodayEntry>> tasksInRange(Ref ref, String from, String to) =>
    ref.watch(tasksRepositoryProvider).watchRange(from, to);

@riverpod
Stream<List<TodayEntry>> completedTasks(Ref ref) => ref.watch(tasksRepositoryProvider).watchCompleted();

@Riverpod(keepAlive: true)
NotificationService notificationService(Ref ref) => NotificationService();

/// When reminders fire for tasks without a start time (HH:MM).
@Riverpod(keepAlive: true)
class DefaultReminderTime extends _$DefaultReminderTime {
  static const _key = 'default_reminder_time';

  @override
  String build() => ref.watch(sharedPreferencesProvider).getString(_key) ?? '09:00';

  Future<void> set(String hhmm) async {
    await ref.read(sharedPreferencesProvider).setString(_key, hhmm);
    state = hhmm;
  }
}

/// Mirrors reminders of the next two weeks into scheduled notifications.
@Riverpod(keepAlive: true)
void reminderScheduler(Ref ref) {
  if (!NotificationService.supported) return;
  final day = ref.watch(currentDayProvider);
  final defaultTime = ref.watch(defaultReminderTimeProvider);
  final service = ref.watch(notificationServiceProvider);
  final until = dateKey(parseDateKey(day).add(const Duration(days: 14)));

  Timer? debounce;
  final sub = ref.watch(tasksRepositoryProvider).watchWithReminders(day, until).listen((tasks) {
    debounce?.cancel();
    debounce = Timer(const Duration(seconds: 1), () {
      service.replaceAll(planReminders(tasks, now: DateTime.now(), defaultTime: defaultTime));
    });
  });
  ref.onDispose(() {
    sub.cancel();
    debounce?.cancel();
  });
}
