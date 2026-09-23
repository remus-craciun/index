import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';
import '../../../core/ids.dart';
import '../../../core/time.dart';
import '../domain/plan_models.dart';

/// Local-first storage for learning plans and milestones. See
/// [TasksRepository] for the write conventions.
class PlansRepository {
  PlansRepository(this.db, {required this.onChanged});

  final AppDatabase db;
  final void Function() onChanged;

  Stream<List<PlanSummary>> watchPlans() {
    return db
        .customSelect(
          '''
          SELECT p.*,
                 COUNT(t.id) AS total_tasks,
                 COALESCE(SUM(CASE WHEN t.status <> 'pending' THEN 1 ELSE 0 END), 0) AS done_tasks
          FROM learning_plans p
          LEFT JOIN milestones m ON m.plan_id = p.id AND m.deleted_at IS NULL
          LEFT JOIN tasks t ON t.milestone_id = m.id AND t.deleted_at IS NULL
          WHERE p.deleted_at IS NULL
          GROUP BY p.id
          ORDER BY CASE p.status WHEN 'active' THEN 0 WHEN 'completed' THEN 1 ELSE 2 END, p.created_at DESC
          ''',
          readsFrom: {db.learningPlans, db.milestones, db.tasks},
        )
        .watch()
        .map((rows) => rows
            .map((r) => PlanSummary(
                  plan: db.learningPlans.map(r.data),
                  totalTasks: r.read<int>('total_tasks'),
                  doneTasks: r.read<int>('done_tasks'),
                ))
            .toList());
  }

  /// Emits whenever the plan, its milestones or tasks change.
  Stream<PlanDetail?> watchPlan(String id) {
    return db
        .customSelect('SELECT 1', readsFrom: {db.learningPlans, db.milestones, db.tasks})
        .watch()
        .asyncMap((_) => _loadPlan(id));
  }

  Future<PlanDetail?> _loadPlan(String id) async {
    final plan = await (db.select(db.learningPlans)..where((p) => p.id.equals(id) & p.deletedAt.isNull()))
        .getSingleOrNull();
    if (plan == null) return null;
    final milestones = await (db.select(db.milestones)
          ..where((m) => m.planId.equals(id) & m.deletedAt.isNull())
          ..orderBy([(m) => OrderingTerm(expression: m.orderIndex), (m) => OrderingTerm(expression: m.createdAt)]))
        .get();
    final ids = milestones.map((m) => m.id).toList();
    final tasks = ids.isEmpty
        ? <TaskRow>[]
        : await (db.select(db.tasks)
              ..where((t) => t.milestoneId.isIn(ids) & t.deletedAt.isNull())
              ..orderBy([
                (t) => OrderingTerm(expression: t.scheduledDate.isNull()),
                (t) => OrderingTerm(expression: t.scheduledDate),
                (t) => OrderingTerm(expression: t.createdAt),
              ]))
            .get();
    return PlanDetail(
      plan: plan,
      milestones: [
        for (final m in milestones)
          MilestoneWithTasks(milestone: m, tasks: tasks.where((t) => t.milestoneId == m.id).toList()),
      ],
    );
  }

  Future<String> createPlan({required String title, String description = '', String? targetDate}) async {
    final now = nowStamp();
    final id = newId();
    await db.into(db.learningPlans).insert(LearningPlansCompanion.insert(
          id: id,
          title: title.trim(),
          description: Value(description.trim()),
          targetDate: Value(targetDate),
          createdAt: now,
          updatedAt: now,
          dirty: const Value(true),
        ));
    onChanged();
    return id;
  }

  Future<void> updatePlan(
    PlanRow plan, {
    String? title,
    String? description,
    Value<String?> targetDate = const Value.absent(),
    String? status,
  }) async {
    await (db.update(db.learningPlans)..where((p) => p.id.equals(plan.id))).write(LearningPlansCompanion(
      title: title == null ? const Value.absent() : Value(title.trim()),
      description: description == null ? const Value.absent() : Value(description.trim()),
      targetDate: targetDate,
      status: status == null ? const Value.absent() : Value(status),
      updatedAt: Value(editStamp(plan.updatedAt)),
      dirty: const Value(true),
    ));
    onChanged();
  }

  /// Soft-deletes the plan with its milestones and tasks. Sync only sends
  /// what the client pushes, so the cascade happens here.
  Future<void> deletePlan(PlanRow plan) async {
    await db.transaction(() async {
      final stamp = editStamp(plan.updatedAt);
      final milestones = await (db.select(db.milestones)..where((m) => m.planId.equals(plan.id))).get();
      for (final m in milestones) {
        await _deleteMilestoneRows(m);
      }
      await (db.update(db.learningPlans)..where((p) => p.id.equals(plan.id))).write(
          LearningPlansCompanion(deletedAt: Value(stamp), updatedAt: Value(stamp), dirty: const Value(true)));
    });
    onChanged();
  }

  Future<void> addMilestone(String planId, String title) async {
    final existing = await (db.select(db.milestones)
          ..where((m) => m.planId.equals(planId) & m.deletedAt.isNull()))
        .get();
    final nextOrder = existing.fold<int>(0, (n, m) => m.orderIndex > n ? m.orderIndex : n) + 1;
    final now = nowStamp();
    await db.into(db.milestones).insert(MilestonesCompanion.insert(
          id: newId(),
          planId: planId,
          title: title.trim(),
          orderIndex: Value(nextOrder),
          createdAt: now,
          updatedAt: now,
          dirty: const Value(true),
        ));
    onChanged();
  }

  Future<void> renameMilestone(MilestoneRow milestone, String title) async {
    await (db.update(db.milestones)..where((m) => m.id.equals(milestone.id))).write(MilestonesCompanion(
      title: Value(title.trim()),
      updatedAt: Value(editStamp(milestone.updatedAt)),
      dirty: const Value(true),
    ));
    onChanged();
  }

  Future<void> deleteMilestone(MilestoneRow milestone) async {
    await db.transaction(() => _deleteMilestoneRows(milestone));
    onChanged();
  }

  Future<void> _deleteMilestoneRows(MilestoneRow milestone) async {
    final tasks = await (db.select(db.tasks)
          ..where((t) => t.milestoneId.equals(milestone.id) & t.deletedAt.isNull()))
        .get();
    for (final t in tasks) {
      final s = editStamp(t.updatedAt);
      await (db.update(db.tasks)..where((r) => r.id.equals(t.id)))
          .write(TasksCompanion(deletedAt: Value(s), updatedAt: Value(s), dirty: const Value(true)));
    }
    if (milestone.deletedAt == null) {
      final s = editStamp(milestone.updatedAt);
      await (db.update(db.milestones)..where((m) => m.id.equals(milestone.id)))
          .write(MilestonesCompanion(deletedAt: Value(s), updatedAt: Value(s), dirty: const Value(true)));
    }
  }

}
