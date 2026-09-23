import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/sync/sync_controller.dart';
import '../../../core/time.dart';
import '../../../core/ui/format.dart';
import '../../../core/ui/widgets.dart';
import '../../repositories.dart';
import '../../shell/sync_indicator.dart';
import '../../tasks/domain/today_entry.dart';
import '../../tasks/presentation/task_tile.dart';

/// The merged daily schedule: overdue, learning steps, then chores.
class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = ref.watch(currentDayProvider);
    final entries = ref.watch(todayEntriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Today'),
            Text(DateFormat('EEEE, d MMMM').format(parseDateKey(day)),
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.history), tooltip: 'History', onPressed: () => context.push('/history')),
          const SyncIndicator(),
          IconButton(icon: const Icon(Icons.settings_outlined), tooltip: 'Settings', onPressed: () => context.push('/settings')),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(syncControllerProvider.notifier).syncNow(),
        child: AsyncView(
          value: entries,
          data: (list) => ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              QuickAddField(
                hint: 'Add a task for today',
                onSubmit: (title) => ref.read(tasksRepositoryProvider).addTask(title: title, scheduledDate: day),
              ),
              if (list.isEmpty)
                const EmptyState(
                  icon: Icons.wb_sunny_outlined,
                  title: 'Nothing scheduled today',
                  message: 'Add a task above, or generate a learning plan from the Plans tab.',
                )
              else ...[
                _Summary(entries: list),
                ..._sections(context, list),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _sections(BuildContext context, List<TodayEntry> list) {
    final overdue = list.where((e) => e.isOverdue).toList();
    final scheduled = list.where((e) => !e.isDone && !e.isOverdue && e.isTimed).toList();
    final learning = list.where((e) => !e.isDone && !e.isOverdue && !e.isTimed && e.isLearning).toList();
    final chores = list.where((e) => !e.isDone && !e.isOverdue && !e.isTimed && !e.isLearning).toList();
    final done = list.where((e) => e.isDone).toList();
    final error = Theme.of(context).colorScheme.error;

    Widget tile(TodayEntry e) => TaskTile(
          task: e.task,
          context: e.isLearning ? [e.planTitle, e.milestoneTitle].whereType<String>().join(' · ') : null,
          showDate: e.isOverdue,
          overdue: e.isOverdue,
        );

    return [
      if (overdue.isNotEmpty) ...[SectionHeader('Overdue', color: error), ...overdue.map(tile)],
      if (scheduled.isNotEmpty) ...[const SectionHeader('Scheduled'), ...scheduled.map(tile)],
      if (learning.isNotEmpty) ...[const SectionHeader('Learning'), ...learning.map(tile)],
      if (chores.isNotEmpty) ...[const SectionHeader('Tasks'), ...chores.map(tile)],
      if (done.isNotEmpty) ...[const SectionHeader('Done'), ...done.map(tile)],
    ];
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.entries});

  final List<TodayEntry> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = entries.where((e) => e.isDone).length;
    final remaining = entries
        .where((e) => !e.isDone)
        .fold<int>(0, (n, e) => n + (e.task.estimatedMinutes ?? 0));
    final progress = entries.isEmpty ? 0.0 : done / entries.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            [
              '$done of ${entries.length} done',
              if (remaining > 0) '~${formatMinutes(remaining)} left',
            ].join(' · '),
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: progress, minHeight: 6),
          ),
        ],
      ),
    );
  }
}
