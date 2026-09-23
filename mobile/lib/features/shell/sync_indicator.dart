import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sync/sync_controller.dart';
import '../../core/ui/format.dart';

/// App-bar button showing sync state; tap to sync now.
class SyncIndicator extends ConsumerWidget {
  const SyncIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncControllerProvider);
    final scheme = Theme.of(context).colorScheme;

    final (Widget icon, String tip) = switch (status) {
      SyncStatus(syncing: true) => (
          const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          'Syncing…'
        ),
      SyncStatus(offline: true) => (Icon(Icons.cloud_off_outlined, color: scheme.outline), 'Offline, changes are saved on this device'),
      SyncStatus(error: final String e) => (Icon(Icons.sync_problem, color: scheme.error), 'Sync failed: $e'),
      SyncStatus(lastSyncAt: final DateTime t) => (const Icon(Icons.cloud_done_outlined), 'Synced ${formatRelative(t)}'),
      _ => (const Icon(Icons.cloud_outlined), 'Not synced yet'),
    };

    return IconButton(
      tooltip: tip,
      icon: icon,
      onPressed: status.syncing
          ? null
          : () {
              ref.read(syncControllerProvider.notifier).syncNow();
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(content: Text(tip), duration: const Duration(seconds: 2)));
            },
    );
  }
}
