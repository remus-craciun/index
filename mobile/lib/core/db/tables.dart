import 'package:drift/drift.dart';

/// Local mirrors of the server's syncable tables. `dirty` marks rows with
/// local changes not yet acknowledged by the server; the sync engine pushes
/// every dirty row. Deletes are tombstones (`deletedAt`) until synced.

@DataClassName('PlanRow')
class LearningPlans extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get targetDate => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();
  TextColumn get deletedAt => text().nullable()();
  BoolColumn get dirty => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('MilestoneRow')
class Milestones extends Table {
  TextColumn get id => text()();
  TextColumn get planId => text()();
  TextColumn get title => text()();
  IntColumn get orderIndex => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('active'))();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();
  TextColumn get deletedAt => text().nullable()();
  BoolColumn get dirty => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Repeating-task rule. Occurrences are materialised as [Tasks] rows by
/// the recurrence generator; see lib/features/routines.
@DataClassName('RecurrenceRow')
class Recurrences extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get notes => text().withDefault(const Constant(''))();

  /// 'daily': every [repeatInterval] days from [startDate] ([weekdays]
  /// ignored). 'weekly': on [weekdays], every [repeatInterval] weeks counted
  /// from the Monday-based week containing [startDate]. 'monthly': on
  /// [monthDay] (clamped to the month's last day), every [repeatInterval]
  /// months counted from [startDate]'s month.
  TextColumn get frequency => text().withDefault(const Constant('weekly'))();
  IntColumn get repeatInterval => integer().withDefault(const Constant(1))();
  IntColumn get monthDay => integer().nullable()();

  /// Bitmask of ISO weekdays: Monday = 1, Tuesday = 2, ... Sunday = 64.
  IntColumn get weekdays => integer()();
  TextColumn get startTime => text().nullable()();
  TextColumn get endTime => text().nullable()();
  IntColumn get estimatedMinutes => integer().nullable()();
  IntColumn get reminderMinutes => integer().nullable()();
  TextColumn get startDate => text()();
  TextColumn get endDate => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();
  TextColumn get deletedAt => text().nullable()();
  BoolColumn get dirty => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('TaskRow')
class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get milestoneId => text().nullable()();

  /// Set on occurrences of a [Recurrences] rule.
  TextColumn get recurrenceId => text().nullable()();
  TextColumn get title => text()();
  TextColumn get notes => text().withDefault(const Constant(''))();
  TextColumn get scheduledDate => text().nullable()();

  /// Optional time window on [scheduledDate], `HH:MM` local time.
  TextColumn get startTime => text().nullable()();
  TextColumn get endTime => text().nullable()();
  IntColumn get estimatedMinutes => integer().nullable()();

  /// Remind this many minutes before the start (09:00 without a start time).
  IntColumn get reminderMinutes => integer().nullable()();
  TextColumn get status => text().withDefault(const Constant('pending'))();

  /// When the task was completed or skipped; null while pending.
  TextColumn get completedAt => text().nullable()();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();
  TextColumn get deletedAt => text().nullable()();
  BoolColumn get dirty => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Small key/value store for sync bookkeeping (cursor, last sync time).
class KeyValues extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
