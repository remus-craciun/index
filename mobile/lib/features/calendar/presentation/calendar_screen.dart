import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../core/db/app_database.dart';
import '../../../core/time.dart';
import '../../../core/ui/widgets.dart';
import '../../repositories.dart';
import '../../routines/data/routines_repository.dart';
import '../../routines/domain/repeat_rule.dart';
import '../../routines/domain/weekdays.dart';
import '../../shell/sync_indicator.dart';
import '../../tasks/domain/today_entry.dart';
import '../../tasks/presentation/task_tile.dart';

/// Month view of everything scheduled, with the selected day's tasks below.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  DateTime _focused = DateTime.now();
  DateTime _selected = DateTime.now();
  CalendarFormat _format = CalendarFormat.month;

  /// Visible grid range, padded by a week on both sides.
  (String, String) get _range {
    final first = DateTime(_focused.year, _focused.month, 1).subtract(const Duration(days: 7));
    final last = DateTime(_focused.year, _focused.month + 1, 0).add(const Duration(days: 7));
    return (dateKey(first), dateKey(last));
  }

  Future<void> _addTask() async {
    final title = await promptText(context, title: 'New task on ${DateFormat('EEE, d MMM').format(_selected)}', confirm: 'Add');
    if (title == null) return;
    await ref.read(tasksRepositoryProvider).addTask(title: title, scheduledDate: dateKey(_selected));
  }

  @override
  Widget build(BuildContext context) {
    final (from, to) = _range;
    final entries = ref.watch(tasksInRangeProvider(from, to)).value ?? const <TodayEntry>[];
    final routines = ref.watch(routinesProvider).value ?? const <RecurrenceRow>[];
    final byDay = <String, List<TodayEntry>>{};
    for (final e in entries) {
      byDay.putIfAbsent(e.task.scheduledDate!, () => []).add(e);
    }
    final previews = _routinePreviews(routines, from, to);
    final theme = Theme.of(context);

    final selectedKey = dateKey(_selected);
    final dayEntries = [...?byDay[selectedKey]]..sort(compareTodayEntries);
    final dayPreviews = previews[selectedKey] ?? const <RecurrenceRow>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
        actions: [
          IconButton(
            icon: const Icon(Icons.today),
            tooltip: 'Jump to today',
            onPressed: () => setState(() => _focused = _selected = DateTime.now()),
          ),
          const SyncIndicator(),
        ],
      ),
      floatingActionButton: FloatingActionButton(heroTag: 'calendar-add', onPressed: _addTask, tooltip: 'Add task on this day', child: const Icon(Icons.add)),
      body: Column(
        children: [
          TableCalendar<Object>(
            firstDay: DateTime(2020),
            lastDay: DateTime(DateTime.now().year + 5, 12, 31),
            focusedDay: _focused,
            startingDayOfWeek: StartingDayOfWeek.monday,
            calendarFormat: _format,
            availableCalendarFormats: const {CalendarFormat.month: 'Month', CalendarFormat.twoWeeks: '2 weeks', CalendarFormat.week: 'Week'},
            onFormatChanged: (f) => setState(() => _format = f),
            selectedDayPredicate: (d) => isSameDay(d, _selected),
            onDaySelected: (selected, focused) => setState(() {
              _selected = selected;
              _focused = focused;
            }),
            onPageChanged: (focused) => setState(() => _focused = focused),
            eventLoader: (d) {
              final key = dateKey(d);
              return [...?byDay[key], ...?previews[key]];
            },
            calendarStyle: CalendarStyle(
              markersMaxCount: 3,
              markerSize: 5,
              markerDecoration: BoxDecoration(color: theme.colorScheme.primary, shape: BoxShape.circle),
              todayDecoration: BoxDecoration(color: theme.colorScheme.primaryContainer, shape: BoxShape.circle),
              todayTextStyle: TextStyle(color: theme.colorScheme.onPrimaryContainer),
              selectedDecoration: BoxDecoration(color: theme.colorScheme.primary, shape: BoxShape.circle),
              selectedTextStyle: TextStyle(color: theme.colorScheme.onPrimary),
              outsideDaysVisible: false,
            ),
            headerStyle: HeaderStyle(
              titleCentered: true,
              formatButtonShowsNext: false,
              titleTextStyle: theme.textTheme.titleMedium!,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                SectionHeader(DateFormat('EEEE, d MMMM').format(_selected)),
                if (dayEntries.isEmpty && dayPreviews.isEmpty)
                  const EmptyState(icon: Icons.event_available, title: 'Nothing scheduled', message: 'Tap + to add a task on this day.'),
                for (final e in dayEntries)
                  TaskTile(
                    task: e.task,
                    context: e.isLearning ? [e.planTitle, e.milestoneTitle].whereType<String>().join(' · ') : null,
                    showDate: false,
                  ),
                for (final r in dayPreviews)
                  ListTile(
                    leading: const Padding(padding: EdgeInsets.all(12), child: Icon(Icons.repeat, size: 20)),
                    title: Text(r.title),
                    subtitle: Text([?formatTimeWindow(r.startTime, r.endTime), 'Planned by routine'].join(' · ')),
                    enabled: false,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Routine occurrences beyond the generated window, shown read-only so
  /// the calendar looks right months ahead.
  Map<String, List<RecurrenceRow>> _routinePreviews(List<RecurrenceRow> routines, String from, String to) {
    final horizon = dateKey(DateTime.now().add(const Duration(days: RoutinesRepository.horizonDays)));
    final out = <String, List<RecurrenceRow>>{};
    if (to.compareTo(horizon) <= 0) return out;
    var d = parseDateKey(from.compareTo(horizon) > 0 ? from : horizon).add(const Duration(days: 1));
    final end = parseDateKey(to);
    while (!d.isAfter(end)) {
      final key = dateKey(d);
      for (final r in routines) {
        if (r.status != 'active' || !occursOn(r, d)) continue;
        if (key.compareTo(r.startDate) < 0 || (r.endDate != null && key.compareTo(r.endDate!) > 0)) continue;
        out.putIfAbsent(key, () => []).add(r);
      }
      d = DateTime(d.year, d.month, d.day + 1);
    }
    return out;
  }
}
