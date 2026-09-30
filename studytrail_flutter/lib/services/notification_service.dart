import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../data/local_prefs.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const int dailyReminderId = 1;

  Future<void> init() async {
    // `tz.local` is UTC until something sets it, and the timezone package
    // can't read the device zone on its own. The old code called
    // `setLocalLocation(tz.local)` — a no-op — so "6 PM" was 18:00 UTC, which
    // is 11:30 PM in India. Scheduling now converts the device's local wall
    // time to UTC instead (see [scheduleDailyReminder]).
    tz.initializeTimeZones();

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    try {
      await _notificationsPlugin.initialize(
        settings: initializationSettings,
      );
    } catch (e) {
      // A plugin failure must never stop the app from starting.
      debugPrint('Notification init failed: $e');
    }
  }

  /// Asks for the Android 13+ notification permission. Exact alarms are not
  /// requested: a daily nudge doesn't need to-the-minute precision, and Play
  /// only allows `USE_EXACT_ALARM` for alarm-clock and calendar apps.
  Future<void> requestPermissions() async {
    if (!Platform.isAndroid) return;
    final plugin = _notificationsPlugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await plugin?.requestNotificationsPermission();
  }

  /// Schedules a daily reminder at [hour]:[minute] device-local time.
  Future<void> scheduleDailyReminder({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
  }) async {
    final now = DateTime.now();
    var local = DateTime(now.year, now.month, now.day, hour, minute);
    if (!local.isAfter(now)) local = local.add(const Duration(days: 1));
    // The same instant expressed in UTC; repeating on its time-of-day keeps it
    // at the same local time for any zone without daylight saving (India).
    final scheduledDate = tz.TZDateTime.from(local.toUtc(), tz.UTC);

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'daily_reminders',
      'Daily Reminders',
      channelDescription: 'Reminders to keep your study streak alive',
      importance: Importance.high,
      priority: Priority.high,
    );

    const NotificationDetails platformDetails =
        NotificationDetails(android: androidDetails);

    await _notificationsPlugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduledDate,
      notificationDetails: platformDetails,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  /// Turns the 6 PM study reminder on or off and remembers the choice. Never
  /// throws: a reminder is a nicety, not something to fail a screen over.
  Future<void> applyDailyReminder({required bool enabled}) async {
    await LocalPrefs.setRemindersEnabled(enabled);
    try {
      if (enabled) {
        await requestPermissions();
        await scheduleDailyReminder(
          id: dailyReminderId,
          title: 'Time to study!',
          body: 'Keep your streak alive and hit your goals today.',
          hour: 18,
          minute: 0,
        );
      } else {
        await _notificationsPlugin.cancel(id: dailyReminderId);
      }
    } catch (e) {
      debugPrint('Daily reminder update failed: $e');
    }
  }

  Future<void> cancelAll() async {
    await _notificationsPlugin.cancelAll();
  }
}
