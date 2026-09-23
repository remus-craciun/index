import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:index_app/core/db/app_database.dart';

void main() {
  test('upgrades a version 1 database in place', () async {
    final db = AppDatabase(NativeDatabase.memory(setup: (raw) {
      // Schema as shipped in version 1.
      raw.execute('''
        CREATE TABLE learning_plans (id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, description TEXT NOT NULL DEFAULT '',
          target_date TEXT NULL, status TEXT NOT NULL DEFAULT 'active', created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
          deleted_at TEXT NULL, dirty INTEGER NOT NULL DEFAULT 0 CHECK (dirty IN (0, 1)));
        CREATE TABLE milestones (id TEXT NOT NULL PRIMARY KEY, plan_id TEXT NOT NULL, title TEXT NOT NULL,
          order_index INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT 'active', created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL, deleted_at TEXT NULL, dirty INTEGER NOT NULL DEFAULT 0 CHECK (dirty IN (0, 1)));
        CREATE TABLE tasks (id TEXT NOT NULL PRIMARY KEY, milestone_id TEXT NULL, title TEXT NOT NULL,
          notes TEXT NOT NULL DEFAULT '', scheduled_date TEXT NULL, estimated_minutes INTEGER NULL,
          status TEXT NOT NULL DEFAULT 'pending', created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
          deleted_at TEXT NULL, dirty INTEGER NOT NULL DEFAULT 0 CHECK (dirty IN (0, 1)));
        CREATE TABLE key_values ("key" TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL);
        INSERT INTO tasks (id, title, status, created_at, updated_at)
          VALUES ('old-done', 'Old', 'completed', '2026-01-01T00:00:00.000Z', '2026-01-02T00:00:00.000Z');
        PRAGMA user_version = 1;
      ''');
    }));
    addTearDown(db.close);

    final t = await (db.select(db.tasks)..where((r) => r.id.equals('old-done'))).getSingle();
    expect(t.completedAt, '2026-01-02T00:00:00.000Z', reason: 'backfilled from updated_at');
    expect(t.recurrenceId, isNull);
    expect(await db.select(db.recurrences).get(), isEmpty);
  });

  test('upgrades a version 2 database (adds routine intervals)', () async {
    final db = AppDatabase(NativeDatabase.memory(setup: (raw) {
      raw.execute('''
        CREATE TABLE learning_plans (id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, description TEXT NOT NULL DEFAULT '',
          target_date TEXT NULL, status TEXT NOT NULL DEFAULT 'active', created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
          deleted_at TEXT NULL, dirty INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE milestones (id TEXT NOT NULL PRIMARY KEY, plan_id TEXT NOT NULL, title TEXT NOT NULL,
          order_index INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT 'active', created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL, deleted_at TEXT NULL, dirty INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE recurrences (id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, notes TEXT NOT NULL DEFAULT '',
          weekdays INTEGER NOT NULL, start_time TEXT NULL, end_time TEXT NULL, estimated_minutes INTEGER NULL,
          reminder_minutes INTEGER NULL, start_date TEXT NOT NULL, end_date TEXT NULL, status TEXT NOT NULL DEFAULT 'active',
          created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT NULL, dirty INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE tasks (id TEXT NOT NULL PRIMARY KEY, milestone_id TEXT NULL, recurrence_id TEXT NULL, title TEXT NOT NULL,
          notes TEXT NOT NULL DEFAULT '', scheduled_date TEXT NULL, start_time TEXT NULL, end_time TEXT NULL,
          estimated_minutes INTEGER NULL, reminder_minutes INTEGER NULL, status TEXT NOT NULL DEFAULT 'pending',
          completed_at TEXT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT NULL,
          dirty INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE key_values ("key" TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL);
        INSERT INTO recurrences (id, title, weekdays, start_date, created_at, updated_at)
          VALUES ('work', 'Work', 31, '2026-03-02', 'x', 'x');
        PRAGMA user_version = 2;
      ''');
    }));
    addTearDown(db.close);

    final r = await db.select(db.recurrences).getSingle();
    expect(r.frequency, 'weekly');
    expect(r.repeatInterval, 1);
    expect(r.monthDay, isNull);
  });

  test('upgrades a version 3 database (adds month_day)', () async {
    final db = AppDatabase(NativeDatabase.memory(setup: (raw) {
      raw.execute('''
        CREATE TABLE learning_plans (id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, description TEXT NOT NULL DEFAULT '',
          target_date TEXT NULL, status TEXT NOT NULL DEFAULT 'active', created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
          deleted_at TEXT NULL, dirty INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE milestones (id TEXT NOT NULL PRIMARY KEY, plan_id TEXT NOT NULL, title TEXT NOT NULL,
          order_index INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT 'active', created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL, deleted_at TEXT NULL, dirty INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE recurrences (id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, notes TEXT NOT NULL DEFAULT '',
          frequency TEXT NOT NULL DEFAULT 'weekly', repeat_interval INTEGER NOT NULL DEFAULT 1,
          weekdays INTEGER NOT NULL, start_time TEXT NULL, end_time TEXT NULL, estimated_minutes INTEGER NULL,
          reminder_minutes INTEGER NULL, start_date TEXT NOT NULL, end_date TEXT NULL, status TEXT NOT NULL DEFAULT 'active',
          created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT NULL, dirty INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE tasks (id TEXT NOT NULL PRIMARY KEY, milestone_id TEXT NULL, recurrence_id TEXT NULL, title TEXT NOT NULL,
          notes TEXT NOT NULL DEFAULT '', scheduled_date TEXT NULL, start_time TEXT NULL, end_time TEXT NULL,
          estimated_minutes INTEGER NULL, reminder_minutes INTEGER NULL, status TEXT NOT NULL DEFAULT 'pending',
          completed_at TEXT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT NULL,
          dirty INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE key_values ("key" TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL);
        INSERT INTO recurrences (id, title, frequency, repeat_interval, weekdays, start_date, created_at, updated_at)
          VALUES ('plants', 'Water plants', 'daily', 3, 127, '2026-03-02', 'x', 'x');
        PRAGMA user_version = 3;
      ''');
    }));
    addTearDown(db.close);

    final r = await db.select(db.recurrences).getSingle();
    expect(r.repeatInterval, 3);
    expect(r.monthDay, isNull);
  });
}
