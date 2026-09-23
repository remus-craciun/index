import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/time.dart';
import '../../../core/ui/format.dart';
import '../../../core/ui/pickers.dart';
import '../../../core/ui/widgets.dart';
import '../../repositories.dart';
import '../domain/repeat_rule.dart';
import '../domain/weekdays.dart';

/// Starting values for a new routine, e.g. taken from an existing task.
class RoutineDraft {
  const RoutineDraft({
    this.title = '',
    this.notes = '',
    this.frequency = Frequency.weekly,
    this.repeatInterval = 1,
    this.weekdays = Weekdays.workdays,
    this.monthDay,
    this.startTime,
    this.endTime,
    this.reminderMinutes,
    this.startDate,
  });

  final String title;
  final String notes;
  final String frequency;
  final int repeatInterval;
  final int weekdays;
  final int? monthDay;
  final String? startTime;
  final String? endTime;
  final int? reminderMinutes;
  final String? startDate;
}

/// Create a routine (optionally from [draft], replacing [replacesTask]),
/// or edit [routine].
class RoutineEditorScreen extends ConsumerStatefulWidget {
  const RoutineEditorScreen({super.key, this.routine, this.draft, this.replacesTask});

  final RecurrenceRow? routine;
  final RoutineDraft? draft;

  /// A one-off task that becomes this routine; deleted when it is saved.
  final TaskRow? replacesTask;

  @override
  ConsumerState<RoutineEditorScreen> createState() => _RoutineEditorScreenState();
}

class _RoutineEditorScreenState extends ConsumerState<RoutineEditorScreen> {
  late final RoutineDraft _d = widget.draft ?? const RoutineDraft();
  late final _title = TextEditingController(text: widget.routine?.title ?? _d.title);
  late final _notes = TextEditingController(text: widget.routine?.notes ?? _d.notes);
  late String _frequency = widget.routine?.frequency ?? _d.frequency;
  late int _interval = widget.routine?.repeatInterval ?? _d.repeatInterval;
  late int _weekdays = widget.routine?.weekdays ?? _d.weekdays;
  late int? _monthDay = widget.routine != null ? widget.routine!.monthDay : _d.monthDay;
  late String? _start = widget.routine != null ? widget.routine!.startTime : _d.startTime;
  late String? _end = widget.routine != null ? widget.routine!.endTime : _d.endTime;
  late int? _reminder = widget.routine != null ? widget.routine!.reminderMinutes : _d.reminderMinutes;
  late String _startDate = widget.routine?.startDate ?? _d.startDate ?? todayKey();
  late String? _endDate = widget.routine?.endDate;
  late bool _paused = widget.routine?.status == 'paused';

  bool get _editing => widget.routine != null;

  /// Day of month for monthly routines; defaults to the start date's day.
  int get _effectiveMonthDay => _monthDay ?? parseDateKey(_startDate).day;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      showMessage(context, 'Give the routine a name');
      return;
    }
    final repo = ref.read(routinesRepositoryProvider);
    final r = widget.routine;
    if (r == null) {
      await repo.createRoutine(
        title: title,
        notes: _notes.text,
        frequency: _frequency,
        repeatInterval: _interval,
        weekdays: _weekdays,
        monthDay: _effectiveMonthDay,
        startTime: _start,
        endTime: _end,
        reminderMinutes: _reminder,
        startDate: _startDate,
        endDate: _endDate,
      );
      if (widget.replacesTask != null) await ref.read(tasksRepositoryProvider).deleteTask(widget.replacesTask!);
    } else {
      await repo.updateRoutine(r.copyWith(
        title: title,
        notes: _notes.text.trim(),
        frequency: _frequency,
        repeatInterval: _interval,
        weekdays: _frequency == Frequency.weekly ? _weekdays : Weekdays.everyDay,
        monthDay: Value(_frequency == Frequency.monthly ? _effectiveMonthDay : null),
        startTime: Value(_start),
        endTime: Value(_end),
        estimatedMinutes: const Value(null),
        reminderMinutes: Value(_reminder),
        startDate: _startDate,
        endDate: Value(_endDate),
        status: _paused ? 'paused' : 'active',
      ));
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await confirm(context,
        title: 'Delete routine?',
        message: 'Upcoming occurrences are removed. Ones you already completed stay in your history.');
    if (!ok) return;
    await ref.read(routinesRepositoryProvider).deleteRoutine(widget.routine!);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _pickDate({required bool end}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: parseDateKey(end ? (_endDate ?? _startDate) : _startDate),
      firstDate: end ? parseDateKey(_startDate) : DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null) return;
    setState(() {
      if (end) {
        _endDate = dateKey(picked);
      } else {
        _startDate = dateKey(picked);
        if (_endDate != null && _endDate!.compareTo(_startDate) < 0) _endDate = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final duration = windowMinutes(_start, _end);
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Edit routine' : 'New routine'),
        actions: [
          if (_editing) IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Delete', onPressed: () => guarded(context, _delete)),
          TextButton(onPressed: () => guarded(context, _save), child: const Text('Save')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _title,
            autofocus: !_editing,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Work, Gym, Read 20 pages'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            minLines: 1,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
          ),
          const SizedBox(height: 24),
          Text('Repeat', style: theme.textTheme.titleSmall),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: Frequency.daily, label: Text('Daily')),
              ButtonSegment(value: Frequency.weekly, label: Text('Weekly')),
              ButtonSegment(value: Frequency.monthly, label: Text('Monthly')),
            ],
            selected: {_frequency},
            onSelectionChanged: (s) => setState(() => _frequency = s.first),
          ),
          const SizedBox(height: 12),
          _IntervalStepper(
            value: _interval,
            unit: switch (_frequency) { Frequency.daily => 'day', Frequency.monthly => 'month', _ => 'week' },
            onChanged: (v) => setState(() => _interval = v),
          ),
          if (_frequency == Frequency.weekly) ...[
            const SizedBox(height: 12),
            Text('On', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            WeekdayPicker(mask: _weekdays, onChanged: (m) => setState(() => _weekdays = m)),
          ],
          if (_frequency == Frequency.monthly) ...[
            const SizedBox(height: 12),
            Text('On day', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            _MonthDayPicker(value: _effectiveMonthDay, onChanged: (d) => setState(() => _monthDay = d)),
            if (_effectiveMonthDay > 28)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('In shorter months it falls on the last day.', style: theme.textTheme.bodySmall),
              ),
          ],
          const SizedBox(height: 8),
          Text(
            [
              describeRepeatParts(_frequency, _interval, _weekdays, monthDay: _effectiveMonthDay),
              if (_interval > 1) 'counting from ${formatDay(_startDate)}',
            ].join(', '),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 24),
          Text('Time', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          TimeWindowPicker(
            start: _start,
            end: _end,
            onChanged: (s, e) => setState(() {
              _start = s;
              _end = e;
            }),
          ),
          if (duration != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('${formatMinutes(duration)} per day', style: theme.textTheme.bodySmall),
            ),
          const SizedBox(height: 24),
          Text('Reminder', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          ReminderPicker(value: _reminder, hasStartTime: _start != null, onChanged: (m) => setState(() => _reminder = m)),
          const SizedBox(height: 24),
          Text('Active', style: theme.textTheme.titleSmall),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.play_arrow_outlined),
            title: const Text('Starts'),
            trailing: Text(formatDay(_startDate)),
            onTap: () => _pickDate(end: false),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.stop_outlined),
            title: const Text('Ends'),
            trailing: _endDate == null
                ? const Text('Never')
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(formatDay(_endDate!)),
                    IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _endDate = null)),
                  ]),
            onTap: () => _pickDate(end: true),
          ),
          if (_editing)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.pause_circle_outline),
              title: const Text('Paused'),
              subtitle: const Text('No new occurrences while paused'),
              value: _paused,
              onChanged: (v) => setState(() => _paused = v),
            ),
          const SizedBox(height: 16),
          Text(
            _editing
                ? 'Saving updates upcoming occurrences you haven\'t changed individually.'
                : 'Occurrences appear on Today and in the calendar.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// "Every [ - N + ] day(s)/week(s)".
class _IntervalStepper extends StatelessWidget {
  const _IntervalStepper({required this.value, required this.unit, required this.onChanged});

  final int value;
  final String unit;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text('Every', style: theme.textTheme.bodyLarge),
        const SizedBox(width: 8),
        IconButton.outlined(
          icon: const Icon(Icons.remove),
          tooltip: 'Less often',
          onPressed: value > 1 ? () => onChanged(value - 1) : null,
        ),
        SizedBox(
          width: 44,
          child: Text('$value', textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
        ),
        IconButton.outlined(
          icon: const Icon(Icons.add),
          tooltip: 'More apart',
          onPressed: value < 365 ? () => onChanged(value + 1) : null,
        ),
        const SizedBox(width: 8),
        Text(value == 1 ? unit : '${unit}s', style: theme.textTheme.bodyLarge),
      ],
    );
  }
}

/// Grid of days 1-31, seven per row.
class _MonthDayPicker extends StatelessWidget {
  const _MonthDayPicker({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Phone-sized even on wide screens, so the circles stay compact.
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: _grid(scheme),
      ),
    );
  }

  Widget _grid(ColorScheme scheme) {
    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      children: [
        for (var d = 1; d <= 31; d++)
          Semantics(
            button: true,
            selected: d == value,
            label: 'Day $d',
            child: InkResponse(
              onTap: () => onChanged(d),
              radius: 22,
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: d == value ? scheme.primary : null,
                ),
                child: Text(
                  '$d',
                  style: TextStyle(
                    color: d == value ? scheme.onPrimary : scheme.onSurface,
                    fontWeight: d == value ? FontWeight.w600 : null,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
