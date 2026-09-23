import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/db/app_database.dart';
import '../../../core/time.dart';
import '../../../core/ui/format.dart';
import '../../../core/ui/widgets.dart';
import '../../ai/presentation/plan_revise_sheet.dart';
import '../../repositories.dart';
import '../../tasks/domain/task_status.dart';
import '../../tasks/presentation/task_tile.dart';
import '../domain/plan_models.dart';

class PlanDetailScreen extends ConsumerWidget {
  const PlanDetailScreen({super.key, required this.planId});

  final String planId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(planDetailProvider(planId));
    return AsyncView(
      value: detail,
      data: (d) => d == null
          ? Scaffold(
              appBar: AppBar(),
              body: const EmptyState(icon: Icons.search_off, title: 'Plan not found', message: 'It may have been deleted.'),
            )
          : _PlanView(detail: d),
    );
  }
}

class _PlanView extends ConsumerWidget {
  const _PlanView({required this.detail});

  final PlanDetail detail;

  Future<void> _menu(BuildContext context, WidgetRef ref, String action) async {
    final repo = ref.read(plansRepositoryProvider);
    final plan = detail.plan;
    switch (action) {
      case 'rename':
        final title = await promptText(context, title: 'Rename plan', initial: plan.title);
        if (title != null) await repo.updatePlan(plan, title: title);
      case 'description':
        final text = await promptText(context, title: 'Description', initial: plan.description, label: 'Description');
        if (text != null) await repo.updatePlan(plan, description: text);
      case 'target':
        if (!context.mounted) return;
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: plan.targetDate != null ? parseDateKey(plan.targetDate!) : now,
          firstDate: DateTime(now.year - 2),
          lastDate: DateTime(now.year + 5),
        );
        if (picked != null) await repo.updatePlan(plan, targetDate: Value(dateKey(picked)));
      case 'milestone':
        final title = await promptText(context, title: 'New milestone', label: 'Milestone title', confirm: 'Add');
        if (title != null) await repo.addMilestone(plan.id, title);
      case 'complete':
        await repo.updatePlan(plan, status: PlanStatus.completed);
      case 'activate':
        await repo.updatePlan(plan, status: PlanStatus.active);
      case 'archive':
        await repo.updatePlan(plan, status: PlanStatus.archived);
      case 'delete':
        final ok = await confirm(context,
            title: 'Delete plan?', message: 'This deletes "${plan.title}" with all its milestones and tasks.');
        if (!ok) return;
        await repo.deletePlan(plan);
        if (context.mounted) context.pop();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final plan = detail.plan;
    final day = ref.watch(currentDayProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(plan.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'Ask AI for changes',
            onPressed: () => showPlanReviseSheet(context, plan.id),
          ),
          PopupMenuButton<String>(
            onSelected: (a) => _menu(context, ref, a),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'milestone', child: Text('Add milestone')),
              const PopupMenuItem(value: 'rename', child: Text('Rename')),
              const PopupMenuItem(value: 'description', child: Text('Edit description')),
              const PopupMenuItem(value: 'target', child: Text('Set target date')),
              const PopupMenuDivider(),
              if (plan.status != PlanStatus.completed) const PopupMenuItem(value: 'complete', child: Text('Mark completed')),
              if (plan.status != PlanStatus.active) const PopupMenuItem(value: 'activate', child: Text('Mark active')),
              if (plan.status != PlanStatus.archived)
                const PopupMenuItem(value: 'archive', child: Text('Archive (hide from Today)')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (plan.description.isNotEmpty)
                  Text(plan.description,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: detail.progress, minHeight: 8),
                ),
                const SizedBox(height: 8),
                Text(
                  [
                    '${detail.doneTasks}/${detail.totalTasks} tasks done',
                    if (plan.targetDate != null) 'target ${formatDay(plan.targetDate!)}',
                    if (plan.status == PlanStatus.archived) 'archived',
                  ].join(' · '),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: () => showPlanReviseSheet(context, plan.id),
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: const Text('Ask AI for changes'),
                ),
              ],
            ),
          ),
          if (detail.milestones.isEmpty)
            EmptyState(
              icon: Icons.flag_outlined,
              title: 'No milestones yet',
              message: 'Break the plan into phases, then add tasks to each.',
              action: FilledButton.tonalIcon(
                onPressed: () => _menu(context, ref, 'milestone'),
                icon: const Icon(Icons.add),
                label: const Text('Add milestone'),
              ),
            ),
          for (final (i, m) in detail.milestones.indexed) _MilestoneSection(index: i + 1, data: m, day: day),
          if (detail.milestones.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton.icon(
                onPressed: () => _menu(context, ref, 'milestone'),
                icon: const Icon(Icons.add),
                label: const Text('Add milestone'),
              ),
            ),
        ],
      ),
    );
  }
}

class _MilestoneSection extends ConsumerWidget {
  const _MilestoneSection({required this.index, required this.data, required this.day});

  final int index;
  final MilestoneWithTasks data;
  final String day;

  Future<void> _menu(BuildContext context, WidgetRef ref, String action) async {
    final repo = ref.read(plansRepositoryProvider);
    final m = data.milestone;
    switch (action) {
      case 'rename':
        final title = await promptText(context, title: 'Rename milestone', initial: m.title);
        if (title != null) await repo.renameMilestone(m, title);
      case 'delete':
        final ok = await confirm(context,
            title: 'Delete milestone?', message: 'This deletes "${m.title}" and its ${data.tasks.length} tasks.');
        if (ok) await repo.deleteMilestone(m);
    }
  }

  Future<void> _addTask(BuildContext context, WidgetRef ref, MilestoneRow m) async {
    final title = await promptText(context, title: 'New task', confirm: 'Add');
    if (title == null) return;
    await ref.read(tasksRepositoryProvider).addTask(title: title, milestoneId: m.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = data.milestone;
    final complete = data.tasks.isNotEmpty && data.doneTasks == data.tasks.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          '$index. ${m.title}',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (complete) const Icon(Icons.check_circle, size: 18),
              Text(' ${data.doneTasks}/${data.tasks.length}', style: Theme.of(context).textTheme.bodySmall),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 20),
                onSelected: (a) => _menu(context, ref, a),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('Rename')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
        ),
        for (final t in data.tasks)
          TaskTile(
            task: t,
            overdue: t.status == TaskStatus.pending && t.scheduledDate != null && t.scheduledDate!.compareTo(day) < 0,
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: TextButton.icon(
              onPressed: () => _addTask(context, ref, m),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add task'),
            ),
          ),
        ),
      ],
    );
  }
}
