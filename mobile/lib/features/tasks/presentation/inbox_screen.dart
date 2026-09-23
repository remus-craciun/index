import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/db/app_database.dart';
import '../../../core/ui/widgets.dart';
import '../../repositories.dart';
import '../../shell/sync_indicator.dart';
import '../domain/task_status.dart';
import 'task_tile.dart';

/// Ad-hoc tasks outside learning plans, grouped by when they're due.
class InboxScreen extends ConsumerStatefulWidget {
  const InboxScreen({super.key});

  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends ConsumerState<InboxScreen> {
  bool _showCompleted = false;

  @override
  Widget build(BuildContext context) {
    final day = ref.watch(currentDayProvider);
    final tasks = ref.watch(inboxTasksProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasks'),
        actions: [
          IconButton(icon: const Icon(Icons.repeat), tooltip: 'Routines', onPressed: () => context.push('/routines')),
          IconButton(icon: const Icon(Icons.history), tooltip: 'History', onPressed: () => context.push('/history')),
          const SyncIndicator(),
          IconButton(icon: const Icon(Icons.settings_outlined), tooltip: 'Settings', onPressed: () => context.push('/settings')),
        ],
      ),
      body: AsyncView(
        value: tasks,
        data: (list) {
          final open = list.where((t) => t.status == TaskStatus.pending).toList();
          final closed = list.where((t) => t.status != TaskStatus.pending).toList()
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          final overdue = open.where((t) => t.scheduledDate != null && t.scheduledDate!.compareTo(day) < 0).toList();
          final today = open.where((t) => t.scheduledDate == day).toList();
          final upcoming = open.where((t) => t.scheduledDate != null && t.scheduledDate!.compareTo(day) > 0).toList();
          final someday = open.where((t) => t.scheduledDate == null).toList();
          final error = Theme.of(context).colorScheme.error;

          Iterable<Widget> tiles(List<TaskRow> ts, {bool overdue = false}) =>
              ts.map((t) => TaskTile(task: t, overdue: overdue, showDate: t.scheduledDate != day));

          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              QuickAddField(
                hint: 'Add a task',
                onSubmit: (title) => ref.read(tasksRepositoryProvider).addTask(title: title),
              ),
              const _RoutinesEntry(),
              if (open.isEmpty && closed.isEmpty)
                const EmptyState(
                  icon: Icons.inbox_outlined,
                  title: 'No tasks yet',
                  message: 'Capture anything here. Tap a task to give it a date so it shows up on Today.',
                ),
              if (overdue.isNotEmpty) ...[SectionHeader('Overdue', color: error), ...tiles(overdue, overdue: true)],
              if (today.isNotEmpty) ...[const SectionHeader('Today'), ...tiles(today)],
              if (upcoming.isNotEmpty) ...[const SectionHeader('Upcoming'), ...tiles(upcoming)],
              if (someday.isNotEmpty) ...[const SectionHeader('Someday'), ...tiles(someday)],
              if (closed.isNotEmpty) ...[
                SectionHeader(
                  'Completed (${closed.length})',
                  trailing: TextButton(
                    onPressed: () => setState(() => _showCompleted = !_showCompleted),
                    child: Text(_showCompleted ? 'Hide' : 'Show'),
                  ),
                ),
                if (_showCompleted) ...tiles(closed.take(50).toList()),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Visible way into routines (repeating tasks) from the Tasks tab.
class _RoutinesEntry extends ConsumerWidget {
  const _RoutinesEntry();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routines = ref.watch(routinesProvider).value ?? const [];
    final active = routines.where((r) => r.status == 'active').length;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Card.outlined(
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: Icon(Icons.repeat, color: theme.colorScheme.primary),
          title: const Text('Repeating tasks'),
          subtitle: Text(routines.isEmpty
              ? 'Daily, weekdays, every N days or weeks'
              : '$active active${routines.length > active ? ', ${routines.length - active} paused' : ''}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/routines'),
        ),
      ),
    );
  }
}
