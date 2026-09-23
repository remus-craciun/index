import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// JSON <-> row mapping for the server's wire format, and the rule for
/// merging server rows into the local database.

Map<String, dynamic> planToJson(PlanRow p) => {
      'id': p.id,
      'title': p.title,
      'description': p.description,
      'target_date': p.targetDate,
      'status': p.status,
      'created_at': p.createdAt,
      'updated_at': p.updatedAt,
      'deleted_at': p.deletedAt,
    };

Map<String, dynamic> milestoneToJson(MilestoneRow m) => {
      'id': m.id,
      'plan_id': m.planId,
      'title': m.title,
      'order_index': m.orderIndex,
      'status': m.status,
      'created_at': m.createdAt,
      'updated_at': m.updatedAt,
      'deleted_at': m.deletedAt,
    };

Map<String, dynamic> recurrenceToJson(RecurrenceRow r) => {
      'id': r.id,
      'title': r.title,
      'notes': r.notes,
      'frequency': r.frequency,
      'repeat_interval': r.repeatInterval,
      'weekdays': r.weekdays,
      'month_day': r.monthDay,
      'start_time': r.startTime,
      'end_time': r.endTime,
      'estimated_minutes': r.estimatedMinutes,
      'reminder_minutes': r.reminderMinutes,
      'start_date': r.startDate,
      'end_date': r.endDate,
      'status': r.status,
      'created_at': r.createdAt,
      'updated_at': r.updatedAt,
      'deleted_at': r.deletedAt,
    };

Map<String, dynamic> taskToJson(TaskRow t) => {
      'id': t.id,
      'milestone_id': t.milestoneId,
      'recurrence_id': t.recurrenceId,
      'title': t.title,
      'notes': t.notes,
      'scheduled_date': t.scheduledDate,
      'start_time': t.startTime,
      'end_time': t.endTime,
      'estimated_minutes': t.estimatedMinutes,
      'reminder_minutes': t.reminderMinutes,
      'status': t.status,
      'completed_at': t.completedAt,
      'created_at': t.createdAt,
      'updated_at': t.updatedAt,
      'deleted_at': t.deletedAt,
    };

PlanRow planFromJson(Map<String, dynamic> j) => PlanRow(
      id: j['id'] as String,
      title: j['title'] as String,
      description: (j['description'] as String?) ?? '',
      targetDate: j['target_date'] as String?,
      status: j['status'] as String,
      createdAt: j['created_at'] as String,
      updatedAt: j['updated_at'] as String,
      deletedAt: j['deleted_at'] as String?,
      dirty: false,
    );

MilestoneRow milestoneFromJson(Map<String, dynamic> j) => MilestoneRow(
      id: j['id'] as String,
      planId: j['plan_id'] as String,
      title: j['title'] as String,
      orderIndex: (j['order_index'] as num).toInt(),
      status: j['status'] as String,
      createdAt: j['created_at'] as String,
      updatedAt: j['updated_at'] as String,
      deletedAt: j['deleted_at'] as String?,
      dirty: false,
    );

RecurrenceRow recurrenceFromJson(Map<String, dynamic> j) => RecurrenceRow(
      id: j['id'] as String,
      title: j['title'] as String,
      notes: (j['notes'] as String?) ?? '',
      frequency: (j['frequency'] as String?) ?? 'weekly',
      repeatInterval: (j['repeat_interval'] as num?)?.toInt() ?? 1,
      weekdays: (j['weekdays'] as num).toInt(),
      monthDay: (j['month_day'] as num?)?.toInt(),
      startTime: j['start_time'] as String?,
      endTime: j['end_time'] as String?,
      estimatedMinutes: (j['estimated_minutes'] as num?)?.toInt(),
      reminderMinutes: (j['reminder_minutes'] as num?)?.toInt(),
      startDate: j['start_date'] as String,
      endDate: j['end_date'] as String?,
      status: j['status'] as String,
      createdAt: j['created_at'] as String,
      updatedAt: j['updated_at'] as String,
      deletedAt: j['deleted_at'] as String?,
      dirty: false,
    );

TaskRow taskFromJson(Map<String, dynamic> j) => TaskRow(
      id: j['id'] as String,
      milestoneId: j['milestone_id'] as String?,
      recurrenceId: j['recurrence_id'] as String?,
      title: j['title'] as String,
      notes: (j['notes'] as String?) ?? '',
      scheduledDate: j['scheduled_date'] as String?,
      startTime: j['start_time'] as String?,
      endTime: j['end_time'] as String?,
      estimatedMinutes: (j['estimated_minutes'] as num?)?.toInt(),
      reminderMinutes: (j['reminder_minutes'] as num?)?.toInt(),
      status: j['status'] as String,
      completedAt: j['completed_at'] as String?,
      createdAt: j['created_at'] as String,
      updatedAt: j['updated_at'] as String,
      deletedAt: j['deleted_at'] as String?,
      dirty: false,
    );

/// Rows as delivered by the server, e.g. a `/sync` response or an AI result.
class RemoteChanges {
  RemoteChanges({
    this.plans = const [],
    this.milestones = const [],
    this.recurrences = const [],
    this.tasks = const [],
  });

  final List<PlanRow> plans;
  final List<MilestoneRow> milestones;
  final List<RecurrenceRow> recurrences;
  final List<TaskRow> tasks;

  factory RemoteChanges.fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> list(String k) =>
        ((j[k] as List?) ?? const []).cast<Map<String, dynamic>>();
    return RemoteChanges(
      plans: list('learning_plans').map(planFromJson).toList(),
      milestones: list('milestones').map(milestoneFromJson).toList(),
      recurrences: list('recurrences').map(recurrenceFromJson).toList(),
      tasks: list('tasks').map(taskFromJson).toList(),
    );
  }

  /// From a nested plan (`GET /plans/{id}` / decompose-plan response).
  factory RemoteChanges.fromPlanDetail(Map<String, dynamic> j) {
    final milestones = <MilestoneRow>[];
    final tasks = <TaskRow>[];
    for (final m in ((j['milestones'] as List?) ?? const []).cast<Map<String, dynamic>>()) {
      milestones.add(milestoneFromJson(m));
      for (final t in ((m['tasks'] as List?) ?? const []).cast<Map<String, dynamic>>()) {
        tasks.add(taskFromJson(t));
      }
    }
    return RemoteChanges(plans: [planFromJson(j)], milestones: milestones, tasks: tasks);
  }

  int get length => plans.length + milestones.length + recurrences.length + tasks.length;
}

/// Merges server rows into the local DB. Must run inside a transaction.
///
/// A server row replaces the local one (and marks it clean) unless the
/// local row has an unsynced edit that is newer, in which case the local
/// edit is kept and will be pushed on the next sync.
Future<void> applyRemote(AppDatabase db, RemoteChanges c) async {
  for (final p in c.plans) {
    final local = await (db.select(db.learningPlans)..where((t) => t.id.equals(p.id))).getSingleOrNull();
    if (_localWins(local?.dirty, local?.updatedAt, p.updatedAt)) continue;
    await db.into(db.learningPlans).insertOnConflictUpdate(p);
  }
  for (final m in c.milestones) {
    final local = await (db.select(db.milestones)..where((t) => t.id.equals(m.id))).getSingleOrNull();
    if (_localWins(local?.dirty, local?.updatedAt, m.updatedAt)) continue;
    await db.into(db.milestones).insertOnConflictUpdate(m);
  }
  for (final r in c.recurrences) {
    final local = await (db.select(db.recurrences)..where((t) => t.id.equals(r.id))).getSingleOrNull();
    if (_localWins(local?.dirty, local?.updatedAt, r.updatedAt)) continue;
    await db.into(db.recurrences).insertOnConflictUpdate(r);
  }
  for (final t in c.tasks) {
    final local = await (db.select(db.tasks)..where((r) => r.id.equals(t.id))).getSingleOrNull();
    if (_localWins(local?.dirty, local?.updatedAt, t.updatedAt)) continue;
    await db.into(db.tasks).insertOnConflictUpdate(t);
  }
}

bool _localWins(bool? dirty, String? localUpdatedAt, String remoteUpdatedAt) =>
    dirty == true && localUpdatedAt != null && localUpdatedAt.compareTo(remoteUpdatedAt) > 0;

/// Drops tombstones the server already knows about.
///
/// Routine tombstones and tombstones of routine occurrences are kept:
/// occurrences are generated locally with deterministic IDs, and the
/// generator needs these to know what not to (re)generate.
Future<void> purgeSyncedTombstones(AppDatabase db) async {
  await (db.delete(db.tasks)
        ..where((t) => t.deletedAt.isNotNull() & t.dirty.equals(false) & t.recurrenceId.isNull()))
      .go();
  await (db.delete(db.milestones)..where((t) => t.deletedAt.isNotNull() & t.dirty.equals(false))).go();
  await (db.delete(db.learningPlans)..where((t) => t.deletedAt.isNotNull() & t.dirty.equals(false))).go();
}

/// Used on a server-requested reset: forget everything already synced.
/// Routine occurrences are regenerated afterwards.
Future<void> deleteCleanRows(AppDatabase db) async {
  await (db.delete(db.tasks)..where((t) => t.dirty.equals(false))).go();
  await (db.delete(db.recurrences)..where((t) => t.dirty.equals(false))).go();
  await (db.delete(db.milestones)..where((t) => t.dirty.equals(false))).go();
  await (db.delete(db.learningPlans)..where((t) => t.dirty.equals(false))).go();
}

