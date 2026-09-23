/// Canonical encodings shared with the server.
///
/// Timestamps are UTC with millisecond precision in a fixed-width form
/// (`2026-01-02T03:04:05.678Z`), so string comparison equals chronological
/// comparison. Calendar dates are `YYYY-MM-DD` in the device's local zone.
library;

String formatStamp(DateTime t) {
  final u = t.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  String three(int v) => v.toString().padLeft(3, '0');
  return '${u.year.toString().padLeft(4, '0')}-${two(u.month)}-${two(u.day)}'
      'T${two(u.hour)}:${two(u.minute)}:${two(u.second)}.${three(u.millisecond)}Z';
}

String nowStamp() => formatStamp(DateTime.now());

/// A timestamp for a local edit of a row last stamped [previous]. It is
/// strictly later than [previous] even if the device clock is behind the
/// clock that produced it, so the edit wins last-write-wins against the
/// version it was based on.
String editStamp(String? previous) {
  final now = DateTime.now().toUtc();
  if (previous == null) return formatStamp(now);
  final prev = DateTime.tryParse(previous);
  if (prev == null || now.isAfter(prev)) return formatStamp(now);
  return formatStamp(prev.add(const Duration(milliseconds: 1)));
}

String dateKey(DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}';
}

String todayKey() => dateKey(DateTime.now());

DateTime parseDateKey(String key) {
  final p = key.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}
