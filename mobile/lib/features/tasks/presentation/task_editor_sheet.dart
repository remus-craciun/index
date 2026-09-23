import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/time.dart';
import '../../../core/ui/format.dart';
import '../../../core/ui/pickers.dart';
import '../../../core/ui/widgets.dart';
import '../../repositories.dart';
import '../../routines/domain/repeat_rule.dart';
import '../../routines/domain/weekdays.dart';
import '../../routines/presentation/routine_editor_screen.dart';
import '../domain/task_status.dart';

Future<void> showTaskEditor(BuildContext context, TaskRow task) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => TaskEditorSheet(task: task),
  );
}

class TaskEditorSheet extends ConsumerStatefulWidget {
  const TaskEditorSheet({super.key, required this.task});

  final TaskRow task;

  @override
  ConsumerState<TaskEditorSheet> createState() => _TaskEditorSheetState();
}

class _TaskEditorSheetState extends ConsumerState<TaskEditorSheet> {
  late final _title = TextEditingController(text: widget.task.title);
  late final _notes = TextEditingController(text: widget.task.notes);
  late String? _date = widget.task.scheduledDate;
  late int? _minutes = widget.task.estimatedMinutes;
  late String? _start = widget.task.startTime;
  late String? _end = widget.task.endTime;
  late int? _reminder = widget.task.reminderMinutes;
  _Repeat _repeat = _Repeat.never;

  /// Only one-off tasks can be turned into routines.
  bool get _canRepeat => widget.task.milestoneId == null && widget.task.recurrenceId == null;
  late String _status = widget.task.status;
  bool _busy = false;

  static const _minuteOptions = [5, 15, 30, 45, 60, 90, 120];

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      showMessage(context, 'Title is required');
      return;
    }
    if (_repeat != _Repeat.never) return _saveAsRoutine(title);
    final t = widget.task;
    await ref.read(tasksRepositoryProvider).updateTask(
          t,
          title: title != t.title ? title : null,
          notes: _notes.text.trim() != t.notes ? _notes.text : null,
          scheduledDate: _date != t.scheduledDate ? Value(_date) : const Value.absent(),
          estimatedMinutes: _minutes != t.estimatedMinutes ? Value(_minutes) : const Value.absent(),
          startTime: _start != t.startTime ? Value(_start) : const Value.absent(),
          endTime: _end != t.endTime ? Value(_end) : const Value.absent(),
          reminderMinutes: _reminder != t.reminderMinutes ? Value(_reminder) : const Value.absent(),
          status: _status != t.status ? _status : null,
        );
    if (mounted) Navigator.pop(context);
  }

  /// The day the routine starts from: the task's date, or today.
  String get _anchor => _date ?? todayKey();

  RoutineDraft _draft(String title, {required String frequency, required int weekdays}) => RoutineDraft(
        title: title,
        notes: _notes.text.trim(),
        frequency: frequency,
        weekdays: weekdays,
        startTime: _start,
        endTime: _end,
        reminderMinutes: _reminder,
        startDate: _anchor,
      );

  Future<void> _saveAsRoutine(String title) async {
    final anchor = parseDateKey(_anchor);
    final (frequency, weekdays) = switch (_repeat) {
      _Repeat.daily => (Frequency.daily, Weekdays.everyDay),
      _Repeat.weekdays => (Frequency.weekly, Weekdays.workdays),
      _Repeat.monthly => (Frequency.monthly, Weekdays.everyDay),
      _ => (Frequency.weekly, Weekdays.bit(anchor.weekday)),
    };
    final monthDay = frequency == Frequency.monthly ? anchor.day : null;
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(routinesRepositoryProvider).createRoutine(
          title: title,
          notes: _notes.text,
          frequency: frequency,
          weekdays: weekdays,
          monthDay: monthDay,
          startTime: _start,
          endTime: _end,
          estimatedMinutes: windowMinutes(_start, _end) == null ? _minutes : null,
          reminderMinutes: _reminder,
          startDate: _anchor,
        );
    await ref.read(tasksRepositoryProvider).deleteTask(widget.task);
    if (mounted) Navigator.pop(context);
    messenger.showSnackBar(SnackBar(
      content: Text('"$title" now repeats: ${describeRepeatParts(frequency, 1, weekdays, monthDay: monthDay).toLowerCase()}'),
    ));
  }

  void _openCustomRepeat() {
    final title = _title.text.trim().isEmpty ? widget.task.title : _title.text.trim();
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(MaterialPageRoute<void>(
      builder: (_) => RoutineEditorScreen(
        draft: _draft(title, frequency: Frequency.weekly, weekdays: Weekdays.bit(parseDateKey(_anchor).weekday)),
        replacesTask: widget.task,
      ),
    ));
  }

  Future<void> _delete() async {
    final repo = ref.read(tasksRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final tombstone = await repo.deleteTask(widget.task);
    if (mounted) Navigator.pop(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Deleted "${widget.task.title}"'),
        action: SnackBarAction(label: 'Undo', onPressed: () => repo.restoreTask(tombstone)),
      ));
  }

  Future<void> _breakdown() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final n = await ref.read(aiRepositoryProvider).breakdownTask(widget.task);
      if (mounted) Navigator.pop(context);
      messenger.showSnackBar(SnackBar(content: Text('Replaced with $n smaller tasks')));
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showMessage(context, errorText(e));
      }
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = _date != null ? parseDateKey(_date!) : now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) setState(() => _date = dateKey(picked));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.task.recurrenceId != null) _RoutineBanner(routineId: widget.task.recurrenceId!),
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              style: theme.textTheme.titleMedium,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              minLines: 2,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Notes', alignLabelWithHint: true),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                InputChip(
                  avatar: const Icon(Icons.event, size: 18),
                  label: Text(_date == null ? 'No date' : formatDay(_date!)),
                  onPressed: _pickDate,
                  onDeleted: _date == null ? null : () => setState(() => _date = null),
                ),
                ActionChip(
                  avatar: const Icon(Icons.today, size: 18),
                  label: const Text('Today'),
                  onPressed: () => setState(() => _date = todayKey()),
                ),
                ActionChip(
                  avatar: const Icon(Icons.redo, size: 18),
                  label: const Text('Tomorrow'),
                  onPressed: () => setState(() => _date = dateKey(DateTime.now().add(const Duration(days: 1)))),
                ),
              ],
            ),
            if (_canRepeat) ...[
              const SizedBox(height: 16),
              Text('Repeat', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final r in _Repeat.values)
                    ChoiceChip(
                      avatar: r == _Repeat.custom ? const Icon(Icons.tune, size: 18) : null,
                      label: Text(switch (r) {
                        _Repeat.never => 'Never',
                        _Repeat.daily => 'Daily',
                        _Repeat.weekdays => 'Weekdays',
                        _Repeat.weekly => 'Weekly on ${Weekdays.short[parseDateKey(_anchor).weekday - 1]}',
                        _Repeat.monthly => 'Monthly on the ${ordinal(parseDateKey(_anchor).day)}',
                        _Repeat.custom => 'Custom…',
                      }),
                      selected: _repeat == r,
                      onSelected: (_) => r == _Repeat.custom ? _openCustomRepeat() : setState(() => _repeat = r),
                    ),
                ],
              ),
              if (_repeat != _Repeat.never)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Saving turns this into a routine starting ${formatDay(_anchor).toLowerCase()}. '
                    'Custom… offers every N days/weeks/months, any weekdays or any day of the month.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
            ],
            const SizedBox(height: 16),
            Text('Time', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            TimeWindowPicker(
              start: _start,
              end: _end,
              onChanged: (s, e) => setState(() {
                _start = s;
                _end = e;
                _minutes = windowMinutes(s, e) ?? _minutes;
              }),
            ),
            const SizedBox(height: 16),
            Text('Reminder', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            ReminderPicker(
              value: _reminder,
              hasStartTime: _start != null,
              onChanged: (m) => setState(() => _reminder = m),
            ),
            const SizedBox(height: 16),
            Text('Estimate', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(label: const Text('None'), selected: _minutes == null, onSelected: (_) => setState(() => _minutes = null)),
                for (final m in {..._minuteOptions, ?_minutes}.toList()..sort())
                  ChoiceChip(
                    label: Text(formatMinutes(m)),
                    selected: _minutes == m,
                    onSelected: (_) => setState(() => _minutes = m),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: TaskStatus.pending, label: Text('To do'), icon: Icon(Icons.radio_button_unchecked)),
                ButtonSegment(value: TaskStatus.completed, label: Text('Done'), icon: Icon(Icons.check_circle_outline)),
                ButtonSegment(value: TaskStatus.skipped, label: Text('Skipped'), icon: Icon(Icons.skip_next_outlined)),
              ],
              selected: {_status},
              onSelectionChanged: (s) => setState(() => _status = s.first),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _busy ? null : _breakdown,
              icon: _busy
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome),
              label: Text(_busy ? 'Breaking down…' : 'Break down with AI'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _busy ? null : () => guarded(context, _delete),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                  style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                ),
                const Spacer(),
                FilledButton(onPressed: _busy ? null : () => guarded(context, _save), child: const Text('Save')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RoutineBanner extends ConsumerWidget {
  const _RoutineBanner({required this.routineId});

  final String routineId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routine = ref.watch(routineProvider(routineId)).value;
    final scheme = Theme.of(context).colorScheme;
    return Card.filled(
      color: scheme.secondaryContainer,
      margin: const EdgeInsets.only(bottom: 16),
      child: ListTile(
        leading: const Icon(Icons.repeat),
        title: Text(routine == null ? 'Part of a routine' : describeRepeat(routine)),
        subtitle: const Text('Changes here apply to this day only.'),
        trailing: routine == null
            ? null
            : TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RoutineEditorScreen(routine: routine)));
                },
                child: const Text('Edit routine'),
              ),
      ),
    );
  }
}

enum _Repeat { never, daily, weekdays, weekly, monthly, custom }
