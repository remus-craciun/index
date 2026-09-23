import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/ui/format.dart';
import '../../repositories.dart';
import '../../routines/domain/weekdays.dart';
import '../domain/task_status.dart';
import 'task_editor_sheet.dart';

/// A task row: checkbox to complete, tap to edit, swipe to delete (undoable).
class TaskTile extends ConsumerWidget {
  const TaskTile({super.key, required this.task, this.context, this.showDate = true, this.overdue = false});

  final TaskRow task;

  /// Extra line such as "Plan · Milestone".
  final String? context;
  final bool showDate;
  final bool overdue;

  @override
  Widget build(BuildContext buildContext, WidgetRef ref) {
    final theme = Theme.of(buildContext);
    final done = task.status == TaskStatus.completed;
    final skipped = task.status == TaskStatus.skipped;
    final repo = ref.read(tasksRepositoryProvider);

    final meta = <String>[
      ?formatTimeWindow(task.startTime, task.endTime),
      ?context,
      if (showDate && task.scheduledDate != null) formatDay(task.scheduledDate!),
      if (task.estimatedMinutes != null && task.estimatedMinutes! > 0) formatMinutes(task.estimatedMinutes!),
      if (skipped) 'Skipped',
    ];

    return Dismissible(
      key: ValueKey('task-${task.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: theme.colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Icon(Icons.delete_outline, color: theme.colorScheme.onErrorContainer),
      ),
      onDismissed: (_) async {
        final messenger = ScaffoldMessenger.of(buildContext);
        final tombstone = await repo.deleteTask(task);
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text('Deleted "${task.title}"'),
            action: SnackBarAction(label: 'Undo', onPressed: () => repo.restoreTask(tombstone)),
          ));
      },
      child: ListTile(
        onTap: () => showTaskEditor(buildContext, task),
        leading: Checkbox(
          value: done,
          onChanged: (_) => repo.toggleCompleted(task),
          shape: const CircleBorder(),
        ),
        title: Text(
          task.title,
          style: done || skipped
              ? TextStyle(decoration: TextDecoration.lineThrough, color: theme.colorScheme.outline)
              : null,
        ),
        subtitle: meta.isEmpty
            ? null
            : Text(
                meta.join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: overdue ? TextStyle(color: theme.colorScheme.error) : null,
              ),
        trailing: _badges(theme),
      ),
    );
  }
}

extension on TaskTile {
  Widget? _badges(ThemeData theme) {
    final icons = [
      if (task.recurrenceId != null) Icons.repeat,
      if (task.reminderMinutes != null && task.status == TaskStatus.pending) Icons.notifications_none,
      if (task.notes.isNotEmpty) Icons.notes,
    ];
    if (icons.isEmpty) return null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final i in icons)
          Padding(padding: const EdgeInsets.only(left: 4), child: Icon(i, size: 16, color: theme.colorScheme.outline)),
      ],
    );
  }
}
