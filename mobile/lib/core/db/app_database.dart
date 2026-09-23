import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

part 'app_database.drift.dart';

@DriftDatabase(tables: [LearningPlans, Milestones, Recurrences, Tasks, KeyValues])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
      : super(executor ??
            driftDatabase(
              name: 'index',
              // On web, SQLite runs as WebAssembly in a worker. Both files live
              // in web/ and come from the drift release matching pubspec.lock;
              // update them together with the drift package.
              web: DriftWebOptions(
                sqlite3Wasm: Uri.parse('sqlite3.wasm'),
                driftWorker: Uri.parse('drift_worker.js'),
              ),
            ));

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await customStatement('CREATE INDEX tasks_scheduled ON tasks (scheduled_date)');
          await customStatement('CREATE INDEX tasks_milestone ON tasks (milestone_id)');
          await customStatement('CREATE INDEX milestones_plan ON milestones (plan_id)');
          await customStatement('CREATE INDEX tasks_recurrence ON tasks (recurrence_id)');
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // Creates recurrences with every current column, so later
            // recurrence columns are only added to v2+ databases below.
            await m.createTable(recurrences);
            await m.addColumn(tasks, tasks.recurrenceId);
            await m.addColumn(tasks, tasks.startTime);
            await m.addColumn(tasks, tasks.endTime);
            await m.addColumn(tasks, tasks.reminderMinutes);
            await m.addColumn(tasks, tasks.completedAt);
            await customStatement('CREATE INDEX tasks_recurrence ON tasks (recurrence_id)');
            // Best guess for tasks completed before completed_at existed.
            await customStatement("UPDATE tasks SET completed_at = updated_at WHERE status <> 'pending'");
          } else {
            if (from < 3) {
              await m.addColumn(recurrences, recurrences.frequency);
              await m.addColumn(recurrences, recurrences.repeatInterval);
            }
            if (from < 4) await m.addColumn(recurrences, recurrences.monthDay);
          }
        },
      );

  Future<String?> getValue(String key) async {
    final row = await (select(keyValues)..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> setValue(String key, String value) =>
      into(keyValues).insertOnConflictUpdate(KeyValue(key: key, value: value));

  Stream<String?> watchValue(String key) =>
      (select(keyValues)..where((t) => t.key.equals(key))).watchSingleOrNull().map((r) => r?.value);

  /// Removes every local row, e.g. when switching to a different server.
  Future<void> wipe() => transaction(() async {
        for (final table in allTables) {
          await delete(table).go();
        }
      });
}
