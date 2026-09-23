import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../network/api_exception.dart';
import '../providers.dart';
import '../session/session_controller.dart';
import 'sync_engine.dart';

part 'sync_controller.g.dart';

class SyncStatus {
  const SyncStatus({this.syncing = false, this.lastSyncAt, this.error, this.offline = false});

  final bool syncing;
  final DateTime? lastSyncAt;
  final String? error;
  final bool offline;

  SyncStatus copyWith({bool? syncing, DateTime? lastSyncAt, String? error, bool clearError = false, bool? offline}) =>
      SyncStatus(
        syncing: syncing ?? this.syncing,
        lastSyncAt: lastSyncAt ?? this.lastSyncAt,
        error: clearError ? null : (error ?? this.error),
        offline: offline ?? this.offline,
      );
}

/// Schedules background sync while logged in: at startup, shortly after
/// local edits, when the app resumes, when connectivity returns, and every
/// few minutes.
@Riverpod(keepAlive: true)
class SyncController extends _$SyncController {
  static const _debounce = Duration(milliseconds: 1500);
  static const _period = Duration(minutes: 5);

  Timer? _debounceTimer;
  bool _running = false;
  bool _again = false;

  @override
  SyncStatus build() {
    final authenticated =
        ref.watch(sessionControllerProvider.select((s) => s.value?.authenticated ?? false));
    if (!authenticated) return const SyncStatus();

    final periodic = Timer.periodic(_period, (_) => syncNow());
    final lifecycle = AppLifecycleListener(onResume: syncNow);
    StreamSubscription<List<ConnectivityResult>>? connectivity;
    try {
      connectivity = Connectivity().onConnectivityChanged.listen(
        (r) {
          if (!r.contains(ConnectivityResult.none)) syncNow();
        },
        onError: (Object _) {},
      );
    } catch (_) {
      // Plugin unavailable (tests); periodic and edit-triggered sync still run.
    }
    ref.onDispose(() {
      periodic.cancel();
      lifecycle.dispose();
      connectivity?.cancel();
      _debounceTimer?.cancel();
    });

    Future.microtask(() async {
      final last = await ref.read(appDatabaseProvider).getValue(SyncEngine.lastSyncKey);
      if (last != null) state = state.copyWith(lastSyncAt: DateTime.tryParse(last));
      await syncNow();
    });
    return const SyncStatus();
  }

  /// Called after every local write; coalesces bursts of edits.
  void requestSync() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, syncNow);
  }

  Future<void> syncNow() async {
    final api = ref.read(apiProvider);
    final authenticated = ref.read(sessionControllerProvider).value?.authenticated ?? false;
    if (api == null || !authenticated) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    state = state.copyWith(syncing: true);
    try {
      final result = await SyncEngine(ref.read(appDatabaseProvider), api.sync).run();
      state = state.copyWith(syncing: false, lastSyncAt: DateTime.now(), clearError: true, offline: false);
      if (result.moreDirty) _again = true;
    } catch (e) {
      final err = ApiException.from(e);
      state = state.copyWith(syncing: false, error: err.isNetwork ? null : err.message, offline: err.isNetwork);
    } finally {
      _running = false;
    }
    if (_again) {
      _again = false;
      requestSync();
    }
  }
}
