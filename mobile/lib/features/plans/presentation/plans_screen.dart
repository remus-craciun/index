import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ui/format.dart';
import '../../../core/ui/widgets.dart';
import '../../repositories.dart';
import '../../shell/sync_indicator.dart';
import '../../tasks/domain/task_status.dart';
import '../domain/plan_models.dart';

class PlansScreen extends ConsumerWidget {
  const PlansScreen({super.key});

  Future<void> _newPlan(BuildContext context, WidgetRef ref) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.auto_awesome),
              title: const Text('Generate with AI'),
              subtitle: const Text('Describe a goal and get milestones and scheduled tasks'),
              onTap: () => Navigator.pop(context, 'ai'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: const Text('Blank plan'),
              subtitle: const Text('Build the milestones yourself'),
              onTap: () => Navigator.pop(context, 'blank'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (choice == 'ai') {
      context.push('/plans/new');
    } else if (choice == 'blank') {
      final title = await promptText(context, title: 'New plan', label: 'Plan title', confirm: 'Create');
      if (title == null || !context.mounted) return;
      final id = await ref.read(plansRepositoryProvider).createPlan(title: title);
      if (context.mounted) context.push('/plans/$id');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(planSummariesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plans'),
        actions: [
          const SyncIndicator(),
          IconButton(icon: const Icon(Icons.settings_outlined), tooltip: 'Settings', onPressed: () => context.push('/settings')),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'plans-new',
        onPressed: () => _newPlan(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('New plan'),
      ),
      body: AsyncView(
        value: plans,
        data: (list) => list.isEmpty
            ? Center(
                child: EmptyState(
                  icon: Icons.school_outlined,
                  title: 'No learning plans yet',
                  message: 'Try "Learn distributed systems in Go in 6 weeks". The AI splits it into milestones '
                      'and daily tasks that show up on Today.',
                  action: FilledButton.icon(
                    onPressed: () => context.push('/plans/new'),
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('Generate a plan'),
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, i) => _PlanCard(summary: list[i]),
              ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.summary});

  final PlanSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = summary.plan;
    final muted = p.status != PlanStatus.active;
    final meta = [
      '${summary.doneTasks}/${summary.totalTasks} tasks',
      if (p.targetDate != null) 'target ${formatDay(p.targetDate!)}',
    ].join(' · ');

    return Card.filled(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/plans/${p.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Opacity(
            opacity: muted ? 0.6 : 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(p.title, style: theme.textTheme.titleMedium)),
                    if (muted)
                      Chip(
                        label: Text(p.status == PlanStatus.archived ? 'Archived' : 'Completed'),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                if (p.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(p.description, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: summary.progress, minHeight: 6),
                ),
                const SizedBox(height: 8),
                Text(meta, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
