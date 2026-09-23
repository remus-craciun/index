import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/notification_service.dart';
import '../../../core/session/session_controller.dart';
import '../../../core/sync/sync_controller.dart';
import '../../../core/ui/format.dart';
import '../../../core/ui/pickers.dart';
import '../../../core/ui/widgets.dart';
import '../../repositories.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider).value;
    final sync = ref.watch(syncControllerProvider);
    final theme = Theme.of(context);

    final syncText = switch (sync) {
      SyncStatus(syncing: true) => 'Syncing…',
      SyncStatus(offline: true) => 'Offline. Changes are saved on this device and sync when you reconnect.',
      SyncStatus(error: final String e) => 'Last sync failed: $e',
      SyncStatus(lastSyncAt: final DateTime t) => 'Last synced ${formatRelative(t)}',
      _ => 'Not synced yet',
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const SectionHeader('Sync'),
          ListTile(
            leading: const Icon(Icons.sync),
            title: const Text('Sync now'),
            subtitle: Text(syncText, style: sync.error != null ? TextStyle(color: theme.colorScheme.error) : null),
            enabled: !sync.syncing,
            onTap: () => ref.read(syncControllerProvider.notifier).syncNow(),
          ),
          const SectionHeader('Reminders'),
          if (NotificationService.supported) const _NotificationTile(),
          ListTile(
            leading: const Icon(Icons.alarm),
            title: const Text('Time for tasks without a start time'),
            subtitle: const Text('Reminders on those tasks count from this time'),
            trailing: Text(ref.watch(defaultReminderTimeProvider)),
            onTap: () async {
              final t = await pickClock(context, initial: ref.read(defaultReminderTimeProvider));
              if (t != null) await ref.read(defaultReminderTimeProvider.notifier).set(t);
            },
          ),
          const SectionHeader('Server'),
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: const Text('Server'),
            subtitle: Text(session?.serverUrl ?? '–'),
          ),
          ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: const Text('Change server'),
            subtitle: const Text('Signs you out. Local data stays until you connect to a different server.'),
            onTap: () async {
              final ok = await confirm(context,
                  title: 'Change server?', message: 'You will be signed out.', action: 'Continue', destructive: false);
              if (ok) await ref.read(sessionControllerProvider.notifier).changeServer();
            },
          ),
          const SectionHeader('Account'),
          ListTile(
            leading: Icon(Icons.logout, color: theme.colorScheme.error),
            title: Text('Sign out', style: TextStyle(color: theme.colorScheme.error)),
            onTap: () async {
              final ok = await confirm(context,
                  title: 'Sign out?',
                  message: 'Unsynced changes stay on this device and sync after you sign in again.',
                  action: 'Sign out');
              if (ok) await ref.read(sessionControllerProvider.notifier).logout();
            },
          ),
        ],
      ),
    );
  }
}

class _NotificationTile extends ConsumerStatefulWidget {
  const _NotificationTile();

  @override
  ConsumerState<_NotificationTile> createState() => _NotificationTileState();
}

class _NotificationTileState extends ConsumerState<_NotificationTile> {
  bool? _enabled;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final on = await ref.read(notificationServiceProvider).enabled();
    if (mounted) setState(() => _enabled = on);
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.notifications_outlined),
      title: const Text('Notifications'),
      subtitle: Text(switch (_enabled) {
        null => 'Checking…',
        true => 'Allowed',
        false => 'Off. Tap to allow reminders.',
      }),
      onTap: _enabled == true
          ? null
          : () async {
              await ref.read(notificationServiceProvider).requestPermission();
              await _check();
            },
    );
  }
}
