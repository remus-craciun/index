import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'reminders.dart';

/// Schedules task reminders as local notifications. Android only; on other
/// platforms (web, tests) every call is a no-op.
class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;
  bool _exact = false;

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'task_reminders',
      'Task reminders',
      channelDescription: 'Reminders before tasks start',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  Future<void> init() async {
    if (!supported || _ready) return;
    tzdata.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } catch (_) {
      // Unknown zone name: fall back to UTC offsets via DateTime.
    }
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    );
    _exact = await _android?.canScheduleExactNotifications() ?? false;
    _ready = true;
  }

  /// Whether the user allowed notifications (Android 13+ asks at runtime).
  Future<bool> enabled() async {
    if (!supported) return false;
    await init();
    return await _android?.areNotificationsEnabled() ?? false;
  }

  /// Asks for notification permission, and for exact alarms so reminders
  /// fire on time. Returns whether notifications are allowed.
  Future<bool> requestPermission() async {
    if (!supported) return false;
    await init();
    final granted = await _android?.requestNotificationsPermission() ?? false;
    if (!(await _android?.canScheduleExactNotifications() ?? false)) {
      await _android?.requestExactAlarmsPermission();
    }
    _exact = await _android?.canScheduleExactNotifications() ?? false;
    return granted;
  }

  /// Replaces every scheduled reminder with [reminders].
  Future<void> replaceAll(List<PlannedReminder> reminders) async {
    if (!supported) return;
    await init();
    await _plugin.cancelAllPendingNotifications();
    for (final r in reminders) {
      await _plugin.zonedSchedule(
        id: r.id,
        title: r.title,
        body: r.body,
        payload: r.taskId,
        scheduledDate: tz.TZDateTime.from(r.at, tz.local),
        notificationDetails: _details,
        // Without the exact-alarm permission Android may delay reminders a
        // few minutes, which beats not showing them at all.
        androidScheduleMode:
            _exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }
}
