abstract final class TaskStatus {
  static const pending = 'pending';
  static const completed = 'completed';
  static const skipped = 'skipped';
}

abstract final class PlanStatus {
  static const active = 'active';
  static const completed = 'completed';
  static const archived = 'archived';
}
