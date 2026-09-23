import '../../../core/db/app_database.dart';
import '../../tasks/domain/task_status.dart';

class PlanSummary {
  const PlanSummary({required this.plan, required this.totalTasks, required this.doneTasks});

  final PlanRow plan;
  final int totalTasks;
  final int doneTasks;

  double get progress => totalTasks == 0 ? 0 : doneTasks / totalTasks;
}

class MilestoneWithTasks {
  const MilestoneWithTasks({required this.milestone, required this.tasks});

  final MilestoneRow milestone;
  final List<TaskRow> tasks;

  int get doneTasks => tasks.where((t) => t.status != TaskStatus.pending).length;
}

class PlanDetail {
  const PlanDetail({required this.plan, required this.milestones});

  final PlanRow plan;
  final List<MilestoneWithTasks> milestones;

  int get totalTasks => milestones.fold(0, (n, m) => n + m.tasks.length);
  int get doneTasks => milestones.fold(0, (n, m) => n + m.doneTasks);
  double get progress => totalTasks == 0 ? 0 : doneTasks / totalTasks;
}
