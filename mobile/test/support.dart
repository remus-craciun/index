import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:index_app/core/db/app_database.dart';

AppDatabase memoryDb() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(NativeDatabase.memory());
}

/// Minimal in-Dart stand-in for the server's /sync endpoint: last-write-
/// wins on updated_at, revision cursor, echoes applied rows.
class FakeSyncServer {
  final _rows = <String, Map<String, Map<String, dynamic>>>{
    'learning_plans': {},
    'milestones': {},
    'recurrences': {},
    'tasks': {},
  };
  final _revs = <String, int>{};
  int rev = 0;
  final requests = <Map<String, dynamic>>[];

  /// Simulates an edit made on another device.
  void put(String kind, Map<String, dynamic> row) {
    rev++;
    _rows[kind]![row['id'] as String] = row;
    _revs['$kind/${row['id']}'] = rev;
  }

  Future<Map<String, dynamic>> handle(Map<String, dynamic> body) async {
    requests.add(body);
    final cursor = body['cursor'] as int;
    final changes = (body['changes'] as Map).cast<String, List>();
    final lost = <String, List<Map<String, dynamic>>>{
      'learning_plans': [],
      'milestones': [],
      'recurrences': [],
      'tasks': [],
    };
    final hasChanges = changes.values.any((l) => l.isNotEmpty);
    if (hasChanges) rev++;
    for (final kind in _rows.keys) {
      for (final r in (changes[kind] ?? const []).cast<Map<String, dynamic>>()) {
        final existing = _rows[kind]![r['id']];
        if (existing == null || (r['updated_at'] as String).compareTo(existing['updated_at'] as String) > 0) {
          _rows[kind]![r['id'] as String] = Map.of(r);
          _revs['$kind/${r['id']}'] = rev;
        } else {
          lost[kind]!.add(existing);
        }
      }
    }
    final out = <String, List<Map<String, dynamic>>>{};
    for (final kind in _rows.keys) {
      out[kind] = [
        for (final e in _rows[kind]!.entries)
          if (_revs['$kind/${e.key}']! > cursor) e.value,
        for (final l in lost[kind]!)
          if (_revs['$kind/${l['id']}']! <= cursor) l,
      ];
    }
    return {'cursor': rev, 'reset': false, 'changes': out};
  }

  Map<String, dynamic>? row(String kind, String id) => _rows[kind]![id];
}
