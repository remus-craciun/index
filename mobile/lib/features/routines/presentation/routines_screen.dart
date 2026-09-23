import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/notifications/reminders.dart';
import '../../../core/ui/widgets.dart';
import '../../repositories.dart';
import '../domain/repeat_rule.dart';
import '../domain/weekdays.dart';
import 'routine_editor_screen.dart';

class RoutinesScreen extends ConsumerWidget {
  const RoutinesScreen({super.key});

  void _open(BuildContext context, [RecurrenceRow? r]) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RoutineEditorScreen(routine: r)));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routines = ref.watch(routinesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Routines')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'routines-new',
        onPressed: () => _open(context),
        icon: const Icon(Icons.add),
        label: const Text('New routine'),
      ),
      body: AsyncView(
        value: routines,
        data: (list) => list.isEmpty
            ? Center(
                child: EmptyState(
                  icon: Icons.repeat,
                  title: 'No routines yet',
                  message: 'Add things that repeat, like work from 08:00 to 17:00 on weekdays, '
                      'or a daily walk. They show up on Today automatically.',
                  action: FilledButton.icon(
                    onPressed: () => _open(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Add a routine'),
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.only(bottom: 96),
                children: [for (final r in list) _RoutineTile(routine: r, onTap: () => _open(context, r))],
              ),
      ),
    );
  }
}

class _RoutineTile extends ConsumerWidget {
  const _RoutineTile({required this.routine, required this.onTap});

  final RecurrenceRow routine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final paused = routine.status == 'paused';
    final meta = [
      describeRepeat(routine),
      ?formatTimeWindow(routine.startTime, routine.endTime),
      if (routine.reminderMinutes != null) describeReminder(routine.reminderMinutes!).toLowerCase(),
    ].join(' · ');
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: paused ? theme.colorScheme.surfaceContainerHighest : theme.colorScheme.primaryContainer,
        child: Icon(paused ? Icons.pause : Icons.repeat,
            color: paused ? theme.colorScheme.outline : theme.colorScheme.onPrimaryContainer),
      ),
      title: Text(routine.title, style: paused ? TextStyle(color: theme.colorScheme.outline) : null),
      subtitle: Text(paused ? 'Paused · $meta' : meta),
      trailing: Switch(
        value: !paused,
        onChanged: (on) => ref.read(routinesRepositoryProvider).setPaused(routine, !on),
      ),
    );
  }
}
