import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/repositories.dart';
import '../notifications/notification_service.dart';
import '../notifications/reminders.dart';
import 'widgets.dart';

String formatClock(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

TimeOfDay parseClock(String hhmm) =>
    TimeOfDay(hour: int.parse(hhmm.substring(0, 2)), minute: int.parse(hhmm.substring(3, 5)));

Future<String?> pickClock(BuildContext context, {String? initial, String? help}) async {
  final picked = await showTimePicker(
    context: context,
    initialTime: initial != null ? parseClock(initial) : const TimeOfDay(hour: 9, minute: 0),
    helpText: help,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
      child: child!,
    ),
  );
  return picked == null ? null : formatClock(picked);
}

/// Optional start/end time chips. Clearing the start clears the end; an end
/// earlier than the start is rejected.
class TimeWindowPicker extends StatelessWidget {
  const TimeWindowPicker({super.key, required this.start, required this.end, required this.onChanged});

  final String? start;
  final String? end;
  final void Function(String? start, String? end) onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        InputChip(
          avatar: const Icon(Icons.schedule, size: 18),
          label: Text(start == null ? 'Start time' : 'From $start'),
          onPressed: () async {
            final t = await pickClock(context, initial: start, help: 'Start time');
            if (t == null) return;
            onChanged(t, end != null && end!.compareTo(t) <= 0 ? null : end);
          },
          onDeleted: start == null ? null : () => onChanged(null, null),
        ),
        if (start != null)
          InputChip(
            avatar: const Icon(Icons.schedule_outlined, size: 18),
            label: Text(end == null ? 'End time' : 'Until $end'),
            onPressed: () async {
              final t = await pickClock(context, initial: end ?? start, help: 'End time');
              if (t == null) return;
              if (t.compareTo(start!) <= 0) {
                if (context.mounted) showMessage(context, 'End time must be after the start time');
                return;
              }
              onChanged(start, t);
            },
            onDeleted: end == null ? null : () => onChanged(start, null),
          ),
      ],
    );
  }
}

/// Reminder choice chips. Choosing a reminder the first time asks for the
/// notification permission.
class ReminderPicker extends ConsumerWidget {
  const ReminderPicker({super.key, required this.value, required this.onChanged, this.hasStartTime = true});

  final int? value;
  final ValueChanged<int?> onChanged;
  final bool hasStartTime;

  Future<void> _select(BuildContext context, WidgetRef ref, int? minutes) async {
    onChanged(minutes);
    if (minutes == null || !NotificationService.supported) return;
    final service = ref.read(notificationServiceProvider);
    if (!await service.enabled()) {
      final granted = await service.requestPermission();
      if (!granted && context.mounted) {
        showMessage(context, 'Notifications are turned off for Index. Enable them in system settings.');
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final defaultTime = ref.watch(defaultReminderTimeProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              avatar: const Icon(Icons.notifications_off_outlined, size: 18),
              label: const Text('No reminder'),
              selected: value == null,
              onSelected: (_) => _select(context, ref, null),
            ),
            for (final e in reminderOptions.entries)
              ChoiceChip(label: Text(e.value), selected: value == e.key, onSelected: (_) => _select(context, ref, e.key)),
          ],
        ),
        if (!NotificationService.supported && value != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Reminders only notify on the Android app.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          )
        else if (!hasStartTime && value != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('No start time, so this counts from $defaultTime (change in Settings).',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
      ],
    );
  }
}

/// Monday-first weekday toggles with presets.
class WeekdayPicker extends StatelessWidget {
  const WeekdayPicker({super.key, required this.mask, required this.onChanged});

  final int mask;
  final ValueChanged<int> onChanged;

  static const _letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var d = 1; d <= 7; d++)
              _DayToggle(
                label: _letters[d - 1],
                selected: mask & (1 << (d - 1)) != 0,
                onTap: () {
                  final next = mask ^ (1 << (d - 1));
                  if (next != 0) onChanged(next);
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            ActionChip(label: const Text('Every day'), onPressed: () => onChanged(127)),
            ActionChip(label: const Text('Weekdays'), onPressed: () => onChanged(31)),
            ActionChip(label: const Text('Weekends'), onPressed: () => onChanged(96)),
          ],
        ),
      ],
    );
  }
}

class _DayToggle extends StatelessWidget {
  const _DayToggle({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkResponse(
      onTap: onTap,
      radius: 24,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? scheme.primary : scheme.surfaceContainerHighest,
        ),
        child: Text(label,
            style: TextStyle(fontWeight: FontWeight.w600, color: selected ? scheme.onPrimary : scheme.onSurfaceVariant)),
      ),
    );
  }
}
