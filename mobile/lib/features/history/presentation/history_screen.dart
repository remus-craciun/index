import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/time.dart';
import '../../../core/ui/format.dart';
import '../../../core/ui/widgets.dart';
import '../../repositories.dart';
import '../../tasks/domain/task_status.dart';
import '../../tasks/domain/today_entry.dart';
import '../../tasks/presentation/task_tile.dart';

enum _Filter { all, tasks, routines, learning }

/// Review of completed and skipped tasks, grouped by the day they were done.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  _Filter _filter = _Filter.all;

  bool _keep(TodayEntry e) => switch (_filter) {
        _Filter.all => true,
        _Filter.tasks => !e.isLearning && !e.isRoutine,
        _Filter.routines => e.isRoutine,
        _Filter.learning => e.isLearning,
      };

  @override
  Widget build(BuildContext context) {
    final completed = ref.watch(completedTasksProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: AsyncView(
        value: completed,
        data: (all) {
          final list = all.where(_keep).toList();
          final groups = <String, List<TodayEntry>>{};
          for (final e in list) {
            final day = dateKey(DateTime.parse(e.task.completedAt!).toLocal());
            groups.putIfAbsent(day, () => []).add(e);
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              _Stats(entries: list),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final f in _Filter.values)
                      ChoiceChip(
                        label: Text(switch (f) {
                          _Filter.all => 'All',
                          _Filter.tasks => 'Tasks',
                          _Filter.routines => 'Routines',
                          _Filter.learning => 'Learning',
                        }),
                        selected: _filter == f,
                        onSelected: (_) => setState(() => _filter = f),
                      ),
                  ],
                ),
              ),
              if (list.isEmpty)
                const EmptyState(
                  icon: Icons.history,
                  title: 'Nothing completed yet',
                  message: 'Tasks you tick off show up here, so you can look back on what you got done.',
                ),
              for (final MapEntry(key: day, value: items) in groups.entries) ...[
                SectionHeader(
                  formatDay(day),
                  trailing: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text('${items.where((e) => e.task.status == TaskStatus.completed).length} done',
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                ),
                for (final e in items)
                  TaskTile(
                    task: e.task,
                    showDate: false,
                    context: [
                      DateFormat.Hm().format(DateTime.parse(e.task.completedAt!).toLocal()),
                      if (e.isLearning) ?e.planTitle,
                      if (e.task.scheduledDate != null && e.task.scheduledDate != day)
                        'planned ${formatDay(e.task.scheduledDate!)}',
                    ].join(' · '),
                  ),
              ],
              if (all.length >= 500)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Showing the 500 most recent.', textAlign: TextAlign.center),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.entries});

  final List<TodayEntry> entries;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final done = entries.where((e) => e.task.status == TaskStatus.completed);
    DateTime at(TodayEntry e) => DateTime.parse(e.task.completedAt!).toLocal();

    final todayCount = done.where((e) => !at(e).isBefore(today)).length;
    final week = done.where((e) => !at(e).isBefore(weekStart)).toList();
    final weekMinutes = week.fold<int>(0, (n, e) => n + (e.task.estimatedMinutes ?? 0));

    // Consecutive days (ending today or yesterday) with at least one completion.
    final days = done.map((e) => dateKey(at(e))).toSet();
    var streak = 0;
    var d = days.contains(dateKey(today)) ? today : today.subtract(const Duration(days: 1));
    while (days.contains(dateKey(d))) {
      streak++;
      d = d.subtract(const Duration(days: 1));
    }

    Widget stat(String value, String label) => Expanded(
          child: Column(
            children: [
              Text(value, style: Theme.of(context).textTheme.headlineSmall),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        );

    return Card.filled(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            stat('$todayCount', 'today'),
            stat('${week.length}', 'this week'),
            stat(weekMinutes > 0 ? formatMinutes(weekMinutes) : '–', 'time this week'),
            stat('$streak', 'day streak'),
          ],
        ),
      ),
    );
  }
}
