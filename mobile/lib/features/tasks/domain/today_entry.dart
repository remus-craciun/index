import '../../../core/db/app_database.dart';
import 'task_status.dart';

/// A task in the merged Today schedule, with its learning-plan context.
class TodayEntry {
  const TodayEntry({
    required this.task,
    required this.day,
    this.milestoneTitle,
    this.milestoneOrder,
    this.planId,
    this.planTitle,
  });

  final TaskRow task;
  final String day;
  final String? milestoneTitle;
  final int? milestoneOrder;
  final String? planId;
  final String? planTitle;

  bool get isLearning => task.milestoneId != null;
  bool get isRoutine => task.recurrenceId != null;
  bool get isTimed => task.startTime != null;
  bool get isDone => task.status != TaskStatus.pending;
  bool get isOverdue => !isDone && (task.scheduledDate ?? day).compareTo(day) < 0;
}

/// Orders Today: pending before done; overdue first, then timed tasks by
/// start time, then learning, then the rest; then by date, plan and
/// milestone.
int compareTodayEntries(TodayEntry a, TodayEntry b) {
  int flag(bool v) => v ? 0 : 1;
  final keys = <int>[
    flag(!a.isDone).compareTo(flag(!b.isDone)),
    flag(a.isOverdue).compareTo(flag(b.isOverdue)),
    flag(a.isTimed).compareTo(flag(b.isTimed)),
    (a.task.startTime ?? '').compareTo(b.task.startTime ?? ''),
    flag(a.isLearning).compareTo(flag(b.isLearning)),
    (a.task.scheduledDate ?? '').compareTo(b.task.scheduledDate ?? ''),
    (a.planTitle ?? '').compareTo(b.planTitle ?? ''),
    (a.milestoneOrder ?? 0).compareTo(b.milestoneOrder ?? 0),
    a.task.createdAt.compareTo(b.task.createdAt),
  ];
  return keys.firstWhere((k) => k != 0, orElse: () => 0);
}
