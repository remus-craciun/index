import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/ids.dart';
import '../../../core/time.dart';
import '../../tasks/domain/task_status.dart';
import '../domain/repeat_rule.dart';
import '../domain/weekdays.dart';

/// Routines (repeating tasks) and the generator that turns them into
/// ordinary task rows.
///
/// Occurrences get deterministic IDs derived from (routine, date) and are
/// stamped `createdAt == updatedAt == routine.updatedAt`, so every device
/// generates identical rows. That equality also marks an occurrence as
/// untouched: completing, editing or deleting it bumps `updatedAt` and makes
/// it an ordinary dirty task that syncs.
///
/// Untouched occurrences are local only (clean, never pushed), so the
/// generator may rewrite or hard-delete them freely. Touched ones are left
/// alone, except that deleting a routine also removes its touched future
/// pending occurrences. Tombstones of occurrences are kept locally (see
/// purgeSyncedTombstones) so a deleted occurrence is never regenerated.
class RoutinesRepository {
  RoutinesRepository(this.db, {required this.onChanged, DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final AppDatabase db;
  final void Function() onChanged;
  final DateTime Function() _clock;

  /// How far ahead occurrences are materialised.
  static const horizonDays = 60;

  static const _uuid = Uuid();
  static const _namespace = '6f2c1a52-8a57-4f9e-9a61-3c1f5f0b7d21';

  static String occurrenceId(String routineId, String date) => _uuid.v5(_namespace, '$routineId/$date');

  Stream<List<RecurrenceRow>> watchRoutines() => (db.select(db.recurrences)
        ..where((r) => r.deletedAt.isNull())
        ..orderBy([
          (r) => OrderingTerm(expression: r.status),
          (r) => OrderingTerm(expression: r.startTime.isNull()),
          (r) => OrderingTerm(expression: r.startTime),
          (r) => OrderingTerm(expression: r.title),
        ]))
      .watch();

  Future<RecurrenceRow?> getRoutine(String id) =>
      (db.select(db.recurrences)..where((r) => r.id.equals(id))).getSingleOrNull();

  Future<String> createRoutine({
    required String title,
    String notes = '',
    String frequency = Frequency.weekly,
    int repeatInterval = 1,
    required int weekdays,
    int? monthDay,
    String? startTime,
    String? endTime,
    int? estimatedMinutes,
    int? reminderMinutes,
    String? startDate,
    String? endDate,
  }) async {
    final now = formatStamp(_clock());
    final id = newId();
    await db.into(db.recurrences).insert(RecurrencesCompanion.insert(
          id: id,
          title: title.trim(),
          notes: Value(notes.trim()),
          frequency: Value(frequency),
          repeatInterval: Value(repeatInterval),
          weekdays: frequency == Frequency.weekly ? weekdays : Weekdays.everyDay,
          monthDay: Value(frequency == Frequency.monthly ? (monthDay ?? parseDateKey(startDate ?? dateKey(_clock())).day) : null),
          startTime: Value(startTime),
          endTime: Value(endTime),
          estimatedMinutes: Value(estimatedMinutes),
          reminderMinutes: Value(reminderMinutes),
          startDate: startDate ?? dateKey(_clock()),
          endDate: Value(endDate),
          createdAt: now,
          updatedAt: now,
          dirty: const Value(true),
        ));
    await generate();
    onChanged();
    return id;
  }

  /// Saves [updated] (a modified copy of an existing routine). Future
  /// occurrences that were not individually edited follow the change.
  Future<void> updateRoutine(RecurrenceRow updated) async {
    await db.into(db.recurrences).insertOnConflictUpdate(
          updated.copyWith(updatedAt: editStamp(updated.updatedAt), dirty: true),
        );
    await generate();
    onChanged();
  }

  Future<void> setPaused(RecurrenceRow routine, bool paused) =>
      updateRoutine(routine.copyWith(status: paused ? 'paused' : 'active'));

  /// Deletes the routine and its future pending occurrences. Past and
  /// completed occurrences stay for history.
  Future<void> deleteRoutine(RecurrenceRow routine) async {
    final stamp = editStamp(routine.updatedAt);
    await db.into(db.recurrences).insertOnConflictUpdate(
          routine.copyWith(deletedAt: Value(stamp), updatedAt: stamp, dirty: true),
        );
    await generate();
    onChanged();
  }

  /// Brings occurrences in [today, today + horizon] in line with every
  /// routine. Idempotent; safe to call any time.
  Future<void> generate({DateTime? today}) async {
    final start = today ?? _clock();
    final from = DateTime(start.year, start.month, start.day);
    final fromKey = dateKey(from);
    final horizonKey = dateKey(from.add(const Duration(days: horizonDays)));

    await db.transaction(() async {
      final routines = await db.select(db.recurrences).get();

      // Untouched future occurrences whose routine is gone entirely (e.g.
      // wiped by a sync reset) are dropped too.
      final known = routines.map((r) => r.id).toList();
      final orphans = await (db.select(db.tasks)
            ..where((t) =>
                t.recurrenceId.isNotNull() &
                t.recurrenceId.isNotIn(known) &
                t.scheduledDate.isBiggerOrEqualValue(fromKey)))
          .get();
      for (final o in orphans.where(isUntouched)) {
        await (db.delete(db.tasks)..where((t) => t.id.equals(o.id))).go();
      }

      for (final r in routines) {
        final wanted = <String>{};
        if (r.deletedAt == null && r.status == 'active') {
          var d = r.startDate.compareTo(fromKey) > 0 ? parseDateKey(r.startDate) : from;
          final lastKey = (r.endDate != null && r.endDate!.compareTo(horizonKey) < 0) ? r.endDate! : horizonKey;
          while (dateKey(d).compareTo(lastKey) <= 0) {
            if (occursOn(r, d)) wanted.add(dateKey(d));
            d = DateTime(d.year, d.month, d.day + 1);
          }
        }

        final existing = await (db.select(db.tasks)
              ..where((t) => t.recurrenceId.equals(r.id) & t.scheduledDate.isBiggerOrEqualValue(fromKey)))
            .get();
        final byDate = {for (final t in existing) t.scheduledDate!: t};

        for (final date in wanted) {
          final ex = byDate[date];
          if (ex == null) {
            await db.into(db.tasks).insert(_occurrence(r, date), mode: InsertMode.insertOrIgnore);
          } else if (isUntouched(ex) && !_matches(ex, r)) {
            await db.into(db.tasks).insertOnConflictUpdate(_occurrence(r, date));
          }
          // Touched occurrences and tombstones (deleted by the user) stay.
        }

        for (final ex in existing) {
          if (wanted.contains(ex.scheduledDate) || ex.deletedAt != null) continue;
          if (isUntouched(ex)) {
            await (db.delete(db.tasks)..where((t) => t.id.equals(ex.id))).go();
          } else if (r.deletedAt != null && ex.status == TaskStatus.pending) {
            final stamp = editStamp(ex.updatedAt);
            await (db.update(db.tasks)..where((t) => t.id.equals(ex.id))).write(
                TasksCompanion(deletedAt: Value(stamp), updatedAt: Value(stamp), dirty: const Value(true)));
          }
        }
      }
    });
  }

  /// Generated and never changed since: safe to rewrite or drop.
  static bool isUntouched(TaskRow t) =>
      t.recurrenceId != null && t.deletedAt == null && t.status == TaskStatus.pending && t.createdAt == t.updatedAt;

  bool _matches(TaskRow t, RecurrenceRow r) =>
      t.updatedAt == r.updatedAt &&
      t.title == r.title &&
      t.notes == r.notes &&
      t.startTime == r.startTime &&
      t.endTime == r.endTime &&
      t.estimatedMinutes == _estimate(r) &&
      t.reminderMinutes == r.reminderMinutes;

  int? _estimate(RecurrenceRow r) => r.estimatedMinutes ?? windowMinutes(r.startTime, r.endTime);

  TasksCompanion _occurrence(RecurrenceRow r, String date) => TasksCompanion.insert(
        id: occurrenceId(r.id, date),
        recurrenceId: Value(r.id),
        title: r.title,
        notes: Value(r.notes),
        scheduledDate: Value(date),
        startTime: Value(r.startTime),
        endTime: Value(r.endTime),
        estimatedMinutes: Value(_estimate(r)),
        reminderMinutes: Value(r.reminderMinutes),
        status: const Value(TaskStatus.pending),
        completedAt: const Value(null),
        deletedAt: const Value(null),
        // Deterministic stamps: every device generates an identical row, and
        // createdAt == updatedAt marks it untouched.
        createdAt: r.updatedAt,
        updatedAt: r.updatedAt,
        dirty: const Value(false),
      );
}
