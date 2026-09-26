import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/time.dart';
import '../../../core/ui/format.dart';
import '../../../core/ui/pickers.dart';
import '../../../core/ui/widgets.dart';
import '../../repositories.dart';
import '../../routines/domain/weekdays.dart';

/// Turns a free-form goal into a scheduled learning plan via the server.
class AiPlanScreen extends ConsumerStatefulWidget {
  const AiPlanScreen({super.key});

  @override
  ConsumerState<AiPlanScreen> createState() => _AiPlanScreenState();
}

class _AiPlanScreenState extends ConsumerState<AiPlanScreen> {
  final _prompt = TextEditingController();
  String _start = todayKey();
  String? _target;
  double _minutes = 60;
  int _weekdays = Weekdays.everyDay;
  bool _busy = false;
  String? _error;

  static const _examples = [
    'Learn distributed systems in Go in 6 weeks',
    'Get conversational in Spanish by summer',
    'Prepare for a system design interview',
  ];

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _pick({required bool target}) async {
    final now = DateTime.now();
    final current = target ? _target : _start;
    final picked = await showDatePicker(
      context: context,
      initialDate: current != null ? parseDateKey(current) : parseDateKey(_start).add(const Duration(days: 28)),
      firstDate: target ? parseDateKey(_start) : DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null) return;
    setState(() {
      if (target) {
        _target = dateKey(picked);
      } else {
        _start = dateKey(picked);
        if (_target != null && _target!.compareTo(_start) < 0) _target = null;
      }
    });
  }

  Future<void> _generate() async {
    final prompt = _prompt.text.trim();
    if (prompt.isEmpty) {
      setState(() => _error = 'Describe what you want to learn');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await ref.read(aiRepositoryProvider).generatePlan(
            prompt: prompt,
            startDate: _start,
            targetDate: _target,
            minutesPerDay: _minutes.round(),
            weekdays: _weekdays,
          );
      if (mounted) context.pushReplacement('/plans/$id');
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Generate a plan')),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: _prompt,
                enabled: !_busy,
                autofocus: true,
                minLines: 3,
                maxLines: 6,
                maxLength: 2000,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'What do you want to learn?',
                  hintText: 'e.g. Learn distributed systems in Go in 6 weeks',
                  alignLabelWithHint: true,
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final e in _examples)
                    ActionChip(label: Text(e), onPressed: _busy ? null : () => _prompt.text = e),
                ],
              ),
              const SizedBox(height: 24),
              Text('Schedule', style: theme.textTheme.titleSmall),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.play_arrow_outlined),
                title: const Text('Start'),
                trailing: Text(formatDay(_start)),
                onTap: _busy ? null : () => _pick(target: false),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.flag_outlined),
                title: const Text('Finish by'),
                subtitle: _target == null ? const Text('Optional, the AI picks a sensible length') : null,
                trailing: _target == null
                    ? const Text('Any time')
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(formatDay(_target!)),
                        IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _target = null)),
                      ]),
                onTap: _busy ? null : () => _pick(target: true),
              ),
              const SizedBox(height: 8),
              Text('Days you can work', style: theme.textTheme.bodyMedium),
              Text(
                Weekdays.describe(_weekdays),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              WeekdayPicker(mask: _weekdays, onChanged: (m) => setState(() => _weekdays = m)),
              const SizedBox(height: 16),
              Text('Time per day: ${formatMinutes(_minutes.round())}', style: theme.textTheme.bodyMedium),
              Slider(
                value: _minutes,
                min: 15,
                max: 240,
                divisions: 15,
                label: formatMinutes(_minutes.round()),
                onChanged: _busy ? null : (v) => setState(() => _minutes = v),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _busy ? null : _generate,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Generate plan'),
              ),
              const SizedBox(height: 8),
              Text(
                'Needs a connection. The plan is stored on your server and synced to this device.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          if (_busy)
            Positioned.fill(
              child: ColoredBox(
                color: theme.colorScheme.surface.withValues(alpha: 0.85),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Designing your plan…'),
                      SizedBox(height: 4),
                      Text('This can take up to a minute.'),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
