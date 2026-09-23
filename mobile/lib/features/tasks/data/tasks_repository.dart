import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';
import '../../../core/ids.dart';
import '../../../core/time.dart';
import '../domain/task_status.dart';
import '../domain/today_entry.dart';

/// Local-first task storage. Every write stamps `updatedAt`, marks the row
/// dirty and calls [onChanged] so the sync controller can push it.
class TasksRepository {
  TasksRepository(this.db, {required this.onChanged});

  final AppDatabase db;
  final void Function() onChanged;

  Stream<List<TodayEntry>> watchToday(String day) {
    final t = db.tasks;
    final m = db.milestones;
    final p = db.learningPlans;
    final query = db.select(t).join([
      leftOuterJoin(m, m.id.equalsExp(t.milestoneId)),
      leftOuterJoin(p, p.id.equalsExp(m.planId)),
    ])
      ..where(t.deletedAt.isNull() &
          t.scheduledDate.isNotNull() &
          ((t.status.equals(TaskStatus.pending) & t.scheduledDate.isSmallerOrEqualValue(day)) |
              (t.status.equals(TaskStatus.pending).not() & t.scheduledDate.equals(day))) &
          // A missed routine occurrence doesn't pile up as overdue.
          (t.recurrenceId.isNull() | t.scheduledDate.equals(day)) &
          (t.milestoneId.isNull() |
              (m.deletedAt.isNull() & p.deletedAt.isNull() & p.status.equals(PlanStatus.archived).not())));

    return query.watch().map((rows) {
      final entries = rows.map((r) {
        final milestone = r.readTableOrNull(m);
        final plan = r.readTableOrNull(p);
        return TodayEntry(
          task: r.readTable(t),
          day: day,
          milestoneTitle: milestone?.title,
          milestoneOrder: milestone?.orderIndex,
          planId: plan?.id,
          planTitle: plan?.title,
        );
      }).toList()
        ..sort(compareTodayEntries);
      return entries;
    });
  }

  /// Ad-hoc tasks (not part of a learning plan or a routine).
  Stream<List<TaskRow>> watchInbox() {
    return (db.select(db.tasks)
          ..where((t) => t.deletedAt.isNull() & t.milestoneId.isNull() & t.recurrenceId.isNull())
          ..orderBy([
            (t) => OrderingTerm(expression: t.scheduledDate.isNull()),
            (t) => OrderingTerm(expression: t.scheduledDate),
            (t) => OrderingTerm(expression: t.createdAt),
          ]))
        .watch();
  }

  /// All live tasks scheduled in [from, to] (inclusive date keys), with
  /// plan context, for the calendar.
  Stream<List<TodayEntry>> watchRange(String from, String to) {
    final t = db.tasks;
    final m = db.milestones;
    final p = db.learningPlans;
    final query = db.select(t).join([
      leftOuterJoin(m, m.id.equalsExp(t.milestoneId)),
      leftOuterJoin(p, p.id.equalsExp(m.planId)),
    ])
      ..where(t.deletedAt.isNull() &
          t.scheduledDate.isBetweenValues(from, to) &
          (t.milestoneId.isNull() | (m.deletedAt.isNull() & p.deletedAt.isNull())));
    final today = todayKey();
    return query.watch().map((rows) => rows.map((r) {
          final milestone = r.readTableOrNull(m);
          final plan = r.readTableOrNull(p);
          final task = r.readTable(t);
          return TodayEntry(
            task: task,
            day: today,
            milestoneTitle: milestone?.title,
            milestoneOrder: milestone?.orderIndex,
            planId: plan?.id,
            planTitle: plan?.title,
          );
        }).toList());
  }

  /// Completed and skipped tasks, most recently finished first.
  Stream<List<TodayEntry>> watchCompleted({int limit = 500}) {
    final t = db.tasks;
    final m = db.milestones;
    final p = db.learningPlans;
    final query = db.select(t).join([
      leftOuterJoin(m, m.id.equalsExp(t.milestoneId)),
      leftOuterJoin(p, p.id.equalsExp(m.planId)),
    ])
      ..where(t.deletedAt.isNull() & t.status.equals(TaskStatus.pending).not() & t.completedAt.isNotNull())
      ..orderBy([OrderingTerm.desc(t.completedAt)])
      ..limit(limit);
    final today = todayKey();
    return query.watch().map((rows) => rows.map((r) {
          final milestone = r.readTableOrNull(m);
          final plan = r.readTableOrNull(p);
          return TodayEntry(
            task: r.readTable(t),
            day: today,
            milestoneTitle: milestone?.title,
            milestoneOrder: milestone?.orderIndex,
            planId: plan?.id,
            planTitle: plan?.title,
          );
        }).toList());
  }

  /// Pending tasks with a reminder, scheduled in [from, to].
  Stream<List<TaskRow>> watchWithReminders(String from, String to) => (db.select(db.tasks)
        ..where((t) =>
            t.deletedAt.isNull() &
            t.status.equals(TaskStatus.pending) &
            t.reminderMinutes.isNotNull() &
            t.scheduledDate.isBetweenValues(from, to)))
      .watch();

  Stream<TaskRow?> watchTask(String id) =>
      (db.select(db.tasks)..where((t) => t.id.equals(id) & t.deletedAt.isNull())).watchSingleOrNull();

  Future<TaskRow?> getTask(String id) =>
      (db.select(db.tasks)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<String> addTask({
    required String title,
    String? scheduledDate,
    String? milestoneId,
    int? estimatedMinutes,
    String? startTime,
    String? endTime,
    int? reminderMinutes,
    String notes = '',
  }) async {
    final now = nowStamp();
    final id = newId();
    await db.into(db.tasks).insert(TasksCompanion.insert(
          id: id,
          title: title.trim(),
          milestoneId: Value(milestoneId),
          notes: Value(notes.trim()),
          scheduledDate: Value(scheduledDate),
          startTime: Value(startTime),
          endTime: Value(endTime),
          estimatedMinutes: Value(estimatedMinutes),
          reminderMinutes: Value(reminderMinutes),
          createdAt: now,
          updatedAt: now,
          dirty: const Value(true),
        ));
    onChanged();
    return id;
  }

  Future<void> updateTask(
    TaskRow task, {
    String? title,
    String? notes,
    Value<String?> scheduledDate = const Value.absent(),
    Value<String?> startTime = const Value.absent(),
    Value<String?> endTime = const Value.absent(),
    Value<int?> estimatedMinutes = const Value.absent(),
    Value<int?> reminderMinutes = const Value.absent(),
    String? status,
  }) async {
    final stamp = editStamp(task.updatedAt);
    Value<String?> completedAt = const Value.absent();
    if (status != null && status != task.status) {
      completedAt = Value(status == TaskStatus.pending ? null : (task.completedAt ?? nowStamp()));
    }
    await (db.update(db.tasks)..where((t) => t.id.equals(task.id))).write(TasksCompanion(
      title: title == null ? const Value.absent() : Value(title.trim()),
      notes: notes == null ? const Value.absent() : Value(notes.trim()),
      scheduledDate: scheduledDate,
      startTime: startTime,
      endTime: endTime,
      estimatedMinutes: estimatedMinutes,
      reminderMinutes: reminderMinutes,
      status: status == null ? const Value.absent() : Value(status),
      completedAt: completedAt,
      updatedAt: Value(stamp),
      dirty: const Value(true),
    ));
    onChanged();
  }

  Future<void> toggleCompleted(TaskRow task) => updateTask(
        task,
        status: task.status == TaskStatus.completed ? TaskStatus.pending : TaskStatus.completed,
      );

  /// Soft-deletes [task] and returns the tombstone, for [restoreTask].
  Future<TaskRow> deleteTask(TaskRow task) async {
    final stamp = editStamp(task.updatedAt);
    final tombstone = task.copyWith(deletedAt: Value(stamp), updatedAt: stamp, dirty: true);
    await db.into(db.tasks).insertOnConflictUpdate(tombstone);
    onChanged();
    return tombstone;
  }

  /// Undoes [deleteTask]. Works even if the tombstone was already synced
  /// and purged locally, because the full row is written back.
  Future<void> restoreTask(TaskRow tombstone) async {
    await db.into(db.tasks).insertOnConflictUpdate(
          tombstone.copyWith(deletedAt: const Value(null), updatedAt: editStamp(tombstone.updatedAt), dirty: true),
        );
    onChanged();
  }
}
