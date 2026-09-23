import 'package:intl/intl.dart';

import '../time.dart';

/// "Today", "Tomorrow", "Yesterday", weekday within a week, else "12 Oct".
String formatDay(String key, {String? today}) {
  final ref = parseDateKey(today ?? todayKey());
  final d = parseDateKey(key);
  final diff = d.difference(ref).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';
  if (diff > 1 && diff < 7) return DateFormat.EEEE().format(d);
  if (d.year == ref.year) return DateFormat('EEE, d MMM').format(d);
  return DateFormat('d MMM y').format(d);
}

String formatMinutes(int minutes) {
  if (minutes < 60) return '${minutes}m';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

String formatRelative(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 45) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return DateFormat('d MMM, HH:mm').format(t.toLocal());
}
