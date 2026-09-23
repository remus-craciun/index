import '../db/app_database.dart';
import 'remote_rows.dart';

/// Transport for one sync round trip; implemented by [Api] in the app and
/// by fakes in tests.
typedef SyncTransport = Future<Map<String, dynamic>> Function(Map<String, dynamic> body);

class SyncResult {
  const SyncResult({required this.pushed, required this.pulled, required this.moreDirty});

  final int pushed;
  final int pulled;

  /// Local edits happened during the sync and still need pushing.
  final bool moreDirty;
}

/// Pushes dirty rows and pulls server changes since the stored cursor.
///
/// Protocol (see server/README.md): the request carries full dirty rows and
/// the last cursor; the response carries every row changed since then plus
/// the server's copy of rows whose push lost last-write-wins.
class SyncEngine {
  SyncEngine(this.db, this.transport);

  final AppDatabase db;
  final SyncTransport transport;

  static const cursorKey = 'sync_cursor';
  static const lastSyncKey = 'last_sync_at';

  /// Rows per request. The server accepts up to 5000.
  static const batchSize = 1000;

  Future<SyncResult> run() async {
    final plans = await (db.select(db.learningPlans)..where((t) => t.dirty.equals(true))).get();
    final milestones = await (db.select(db.milestones)..where((t) => t.dirty.equals(true))).get();
    final recurrences = await (db.select(db.recurrences)..where((t) => t.dirty.equals(true))).get();
    final tasks = await (db.select(db.tasks)..where((t) => t.dirty.equals(true))).get();

    // Parents before children, so a batch never references a row the
    // server has not seen yet.
    final queue = <_Pending>[
      for (final p in plans) _Pending('learning_plans', planToJson(p)),
      for (final m in milestones) _Pending('milestones', milestoneToJson(m)),
      for (final r in recurrences) _Pending('recurrences', recurrenceToJson(r)),
      for (final t in tasks) _Pending('tasks', taskToJson(t)),
    ];

    var pulled = 0;
    var offset = 0;
    do {
      final batch = queue.skip(offset).take(batchSize).toList();
      offset += batch.length;
      pulled += await _roundTrip(batch);
    } while (offset < queue.length);

    final stillDirty = await _hasDirty();
    return SyncResult(pushed: queue.length, pulled: pulled, moreDirty: stillDirty);
  }

  Future<int> _roundTrip(List<_Pending> batch) async {
    final cursor = int.tryParse(await db.getValue(cursorKey) ?? '') ?? 0;
    final changes = <String, List<Map<String, dynamic>>>{
      'learning_plans': [],
      'milestones': [],
      'recurrences': [],
      'tasks': [],
    };
    for (final p in batch) {
      changes[p.kind]!.add(p.json);
    }

    final resp = await transport({'cursor': cursor, 'changes': changes});
    final remote = RemoteChanges.fromJson((resp['changes'] as Map).cast<String, dynamic>());
    final newCursor = (resp['cursor'] as num).toInt();
    final reset = resp['reset'] == true;

    await db.transaction(() async {
      if (reset) await deleteCleanRows(db);
      await applyRemote(db, remote);
      await purgeSyncedTombstones(db);
      await db.setValue(cursorKey, '$newCursor');
      await db.setValue(lastSyncKey, DateTime.now().toUtc().toIso8601String());
    });
    return remote.length;
  }

  Future<bool> _hasDirty() async {
    for (final q in [
      db.customSelect('SELECT 1 FROM learning_plans WHERE dirty = 1 LIMIT 1'),
      db.customSelect('SELECT 1 FROM milestones WHERE dirty = 1 LIMIT 1'),
      db.customSelect('SELECT 1 FROM recurrences WHERE dirty = 1 LIMIT 1'),
      db.customSelect('SELECT 1 FROM tasks WHERE dirty = 1 LIMIT 1'),
    ]) {
      if ((await q.get()).isNotEmpty) return true;
    }
    return false;
  }
}

class _Pending {
  _Pending(this.kind, this.json);

  final String kind;
  final Map<String, dynamic> json;
}
