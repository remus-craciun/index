import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';
import '../../../core/network/api.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/sync/remote_rows.dart';
import '../../../core/time.dart';
import '../domain/revision.dart';

/// AI features. These need the server, so they fail fast when offline.
/// Results are written to Drift straight away (they are already stored on
/// the server), so the UI updates without waiting for the next sync.
class AiRepository {
  AiRepository({required this.db, required this.api, required this.syncNow, required this.requestSync});

  final AppDatabase db;
  final Api? api;
  final Future<void> Function() syncNow;
  final void Function() requestSync;

  Api get _api => api ?? (throw ApiException(code: 'no_server', message: 'Not connected to a server'));

  /// Returns the new plan's ID.
  Future<String> generatePlan({
    required String prompt,
    required String startDate,
    String? targetDate,
    required int minutesPerDay,
    int weekdays = 127,
  }) async {
    final json = await _api.decomposePlan(
      prompt: prompt,
      startDate: startDate,
      targetDate: targetDate,
      minutesPerDay: minutesPerDay,
      weekdays: weekdays,
    );
    final remote = RemoteChanges.fromPlanDetail(json);
    await db.transaction(() => applyRemote(db, remote));
    requestSync();
    return remote.plans.single.id;
  }

  /// Asks the AI how it would apply [instruction] to the plan. Local edits
  /// are synced first, so the AI works from the latest version.
  Future<RevisionProposal> proposeRevision(String planId, String instruction) async {
    if (await _planHasUnsyncedChanges(planId)) {
      await syncNow();
      if (await _planHasUnsyncedChanges(planId)) {
        throw ApiException(code: 'not_synced', message: 'Sync the plan before asking for changes.');
      }
    }
    final json = await _api.revisePlan(planId: planId, instruction: instruction, today: todayKey());
    return RevisionProposal.fromJson(json);
  }

  /// Stores [proposal] on the server and mirrors the result locally.
  Future<void> applyRevision(String planId, RevisionProposal proposal) async {
    final json = await _api.applyRevision(
      planId: planId,
      revision: proposal.revision,
      startDate: todayKey(),
      minutesPerDay: proposal.minutesPerDay,
    );
    final remote = RemoteChanges.fromPlanDetail(json);
    final keptMilestones = remote.milestones.map((m) => m.id).toSet();
    final keptTasks = remote.tasks.map((t) => t.id).toSet();
    await db.transaction(() async {
      await applyRemote(db, remote);
      // Rows the revision removed are tombstoned on the server; hide them
      // now, the next sync brings the tombstones.
      final stamp = nowStamp();
      final milestones = await (db.select(db.milestones)..where((m) => m.planId.equals(planId) & m.deletedAt.isNull())).get();
      for (final m in milestones.where((m) => !keptMilestones.contains(m.id) && !m.dirty)) {
        await (db.update(db.milestones)..where((r) => r.id.equals(m.id)))
            .write(MilestonesCompanion(deletedAt: Value(stamp)));
      }
      final ids = milestones.map((m) => m.id).toList();
      if (ids.isNotEmpty) {
        final tasks = await (db.select(db.tasks)..where((t) => t.milestoneId.isIn(ids) & t.deletedAt.isNull())).get();
        for (final t in tasks.where((t) => !keptTasks.contains(t.id) && !t.dirty)) {
          await (db.update(db.tasks)..where((r) => r.id.equals(t.id))).write(TasksCompanion(deletedAt: Value(stamp)));
        }
      }
    });
    requestSync();
  }

  Future<bool> _planHasUnsyncedChanges(String planId) async {
    final rows = await db.customSelect(
      '''
      SELECT 1 FROM learning_plans WHERE id = ?1 AND dirty = 1
      UNION ALL SELECT 1 FROM milestones WHERE plan_id = ?1 AND dirty = 1
      UNION ALL SELECT 1 FROM tasks t JOIN milestones m ON m.id = t.milestone_id WHERE m.plan_id = ?1 AND t.dirty = 1
      LIMIT 1
      ''',
      variables: [Variable.withString(planId)],
    ).get();
    return rows.isNotEmpty;
  }

  /// Replaces [task] with AI-generated subtasks. Unsynced tasks are synced
  /// first, since the server has to know the task.
  Future<int> breakdownTask(TaskRow task) async {
    if (task.dirty) {
      await syncNow();
      final fresh = await (db.select(db.tasks)..where((t) => t.id.equals(task.id))).getSingleOrNull();
      if (fresh == null || fresh.dirty) {
        throw ApiException(code: 'not_synced', message: 'Sync this task before breaking it down.');
      }
    }
    final json = await _api.breakdownTask(task.id);
    final subtasks = ((json['tasks'] as List?) ?? const []).cast<Map<String, dynamic>>().map(taskFromJson).toList();
    await db.transaction(() async {
      await applyRemote(db, RemoteChanges(tasks: subtasks));
      // The server soft-deleted the original; hide it now, the next sync
      // brings the authoritative tombstone.
      final stamp = nowStamp();
      await (db.update(db.tasks)..where((t) => t.id.equals(task.id)))
          .write(TasksCompanion(deletedAt: Value(stamp), dirty: const Value(false)));
    });
    requestSync();
    return subtasks.length;
  }
}
