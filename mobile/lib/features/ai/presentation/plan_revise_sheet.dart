import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/format.dart';
import '../../../core/ui/widgets.dart';
import '../../repositories.dart';
import '../domain/revision.dart';

Future<void> showPlanReviseSheet(BuildContext context, String planId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => PlanReviseSheet(planId: planId),
  );
}

/// Follow-up requests on a plan: ask, preview the changes, apply, repeat.
class PlanReviseSheet extends ConsumerStatefulWidget {
  const PlanReviseSheet({super.key, required this.planId});

  final String planId;

  @override
  ConsumerState<PlanReviseSheet> createState() => _PlanReviseSheetState();
}

enum _Phase { asking, thinking, preview, applying }

class _PlanReviseSheetState extends ConsumerState<PlanReviseSheet> {
  final _request = TextEditingController();
  _Phase _phase = _Phase.asking;
  RevisionProposal? _proposal;
  String? _error;

  /// Requests applied while the sheet is open, newest last.
  final _history = <(String request, String summary)>[];

  static const _suggestions = [
    'Make it lighter',
    'Add more hands-on projects',
    'Spread it over more weeks',
    'Add a milestone on testing',
    'Remove anything too theoretical',
  ];

  @override
  void dispose() {
    _request.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    final text = _request.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Describe what you want changed');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _phase = _Phase.thinking;
      _error = null;
    });
    try {
      final proposal = await ref.read(aiRepositoryProvider).proposeRevision(widget.planId, text);
      if (!mounted) return;
      setState(() {
        _proposal = proposal;
        _phase = _Phase.preview;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorText(e);
          _phase = _Phase.asking;
        });
      }
    }
  }

  Future<void> _apply() async {
    setState(() => _phase = _Phase.applying);
    try {
      await ref.read(aiRepositoryProvider).applyRevision(widget.planId, _proposal!);
      if (!mounted) return;
      setState(() {
        _history.add((_request.text.trim(), _proposal!.summary));
        _request.clear();
        _proposal = null;
        _phase = _Phase.asking;
      });
      showMessage(context, 'Plan updated');
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorText(e);
          _phase = _Phase.preview;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(child: Text('Ask for changes', style: theme.textTheme.titleLarge)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Describe what to change. You\'ll see a preview before anything is saved. '
              'Completed tasks are never touched.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            for (final (request, summary) in _history) _HistoryItem(request: request, summary: summary),
            const SizedBox(height: 16),
            ...switch (_phase) {
              _Phase.asking => _askingView(theme),
              _Phase.thinking => [_busy('Working out the changes…', 'This can take up to a minute.')],
              _Phase.preview => _previewView(theme),
              _Phase.applying => [_busy('Updating your plan…', null)],
            },
          ],
        ),
      ),
    );
  }

  List<Widget> _askingView(ThemeData theme) => [
        TextField(
          controller: _request,
          autofocus: _history.isEmpty,
          minLines: 2,
          maxLines: 5,
          maxLength: 2000,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: _history.isEmpty ? 'What should change?' : 'Anything else?',
            hintText: 'e.g. Week 2 is too heavy, spread it out',
            alignLabelWithHint: true,
            errorText: _error,
            errorMaxLines: 3,
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [for (final s in _suggestions) ActionChip(label: Text(s), onPressed: () => _request.text = s)],
        ),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: _ask, icon: const Icon(Icons.send), label: const Text('Preview changes')),
        if (_history.isNotEmpty)
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
      ];

  List<Widget> _previewView(ThemeData theme) {
    final p = _proposal!;
    return [
      Card.filled(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Proposed changes', style: theme.textTheme.titleSmall),
              if (p.summary.isNotEmpty) ...[const SizedBox(height: 6), Text(p.summary)],
              const SizedBox(height: 8),
              if (p.isEmpty)
                const Text('Nothing would change.')
              else
                for (final c in p.changes) _ChangeRow(change: c),
              const SizedBox(height: 8),
              Text(
                'Pending tasks will be re-spread from today at about ${formatMinutes(p.minutesPerDay)} a day.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: 8),
        Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
      ],
      const SizedBox(height: 16),
      OverflowBar(
        alignment: MainAxisAlignment.spaceBetween,
        overflowAlignment: OverflowBarAlignment.end,
        spacing: 8,
        children: [
          TextButton(
            onPressed: () => setState(() {
              _proposal = null;
              _phase = _Phase.asking;
            }),
            child: const Text('Change request'),
          ),
          FilledButton.icon(
            onPressed: p.isEmpty ? null : _apply,
            icon: const Icon(Icons.check),
            label: const Text('Apply'),
          ),
        ],
      ),
    ];
  }

  Widget _busy(String title, String? subtitle) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(title),
            if (subtitle != null) Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
}

class _ChangeRow extends StatelessWidget {
  const _ChangeRow({required this.change});

  final PlanChange change;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (IconData icon, Color color) = switch (change.action) {
      'added' => (Icons.add_circle_outline, Colors.green.shade600),
      'removed' => (Icons.remove_circle_outline, scheme.error),
      'moved' => (Icons.swap_vert, scheme.tertiary),
      _ => (Icons.edit_outlined, scheme.primary),
    };
    final what = switch (change.kind) { 'milestone' => 'Milestone', 'plan' => 'Plan', _ => 'Task' };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(TextSpan(children: [
              TextSpan(text: '$what ', style: TextStyle(color: scheme.onSurfaceVariant)),
              TextSpan(text: change.title, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (change.detail != null) TextSpan(text: ' · ${change.detail}', style: TextStyle(color: scheme.onSurfaceVariant)),
            ])),
          ),
        ],
      ),
    );
  }
}

class _HistoryItem extends StatelessWidget {
  const _HistoryItem({required this.request, required this.summary});

  final String request;
  final String summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(request, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (summary.isNotEmpty)
                  Text(summary, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
