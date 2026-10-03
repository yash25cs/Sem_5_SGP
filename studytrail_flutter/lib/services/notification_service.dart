import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Local, on-device reminders. Nothing here talks to a server: what to
/// schedule is decided by `ReminderSync`, which reads the student's streak.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  /// The repeating reminder earlier builds scheduled. Cancelled on every sync
  /// so an upgraded install doesn't keep firing it alongside the new ones.
  static const int _legacyDailyId = 1;

  /// One-off reminders for the next [_daysAhead] days: 18:00 "time to study"
  /// at `_studyBase + day`, 21:00 "streak at risk" at `_streakBase + day`.
  /// One-offs rather than a repeating reminder so that today's can be dropped
  /// once the student has studied, without losing tomorrow's.
  static const int _studyBase = 100;
  static const int _streakBase = 200;
  static const int _daysAhead = 7;

  /// Sunday 19:00: the weekly report is ready. Opens it when tapped.
  static const int _weeklyReportId = 300;
  static const String weeklyReportPayload = 'weekly_report';

  /// The payload of a notification the student tapped, until the shell
  /// handles it — including the one that launched the app.
  final ValueNotifier<String?> opened = ValueNotifier(null);

  Future<void> init() async {
    // `tz.local` is UTC until something sets it, and the timezone package
    // can't read the device zone on its own — so reminders are scheduled from
    // the device's local wall time converted to UTC (see [_scheduleOnce]).
    tz.initializeTimeZones();

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    try {
      await _notificationsPlugin.initialize(
        settings: initializationSettings,
        onDidReceiveNotificationResponse: (response) =>
            opened.value = response.payload,
      );
      final launch =
          await _notificationsPlugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        opened.value = launch!.notificationResponse?.payload;
      }
    } catch (e) {
      // A plugin failure must never stop the app from starting.
      debugPrint('Notification init failed: $e');
    }
  }

  /// Asks for the Android 13+ notification permission. Exact alarms are not
  /// requested: a nudge doesn't need to-the-minute precision, and Play only
  /// allows `USE_EXACT_ALARM` for alarm-clock and calendar apps.
  Future<void> requestPermissions() async {
    if (!Platform.isAndroid) return;
    final plugin = _notificationsPlugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await plugin?.requestNotificationsPermission();
  }

  /// Replaces every scheduled reminder with the week ahead.
  ///
  /// * 18:00 each day — skipped today if the student already studied.
  /// * 21:00 each day, only while there is a streak to lose — skipped today
  ///   if they already studied. [streak] is the run they'd be protecting.
  /// * 19:00 on the coming Sunday: the weekly report.
  ///
  /// Never throws: a reminder is a nicety, not something to fail a screen over.
  Future<void> scheduleReminders({
    required bool enabled,
    bool studiedToday = false,
    int streak = 0,
    bool askPermission = false,
  }) async {
    try {
      await _cancelReminders();
      if (!enabled) return;
      if (askPermission) await requestPermissions();

      final now = DateTime.now();
      for (var day = 0; day < _daysAhead; day++) {
        final skipToday = day == 0 && studiedToday;

        final study = _localTime(now, day, 18, 0);
        if (!skipToday && study.isAfter(now)) {
          await _scheduleOnce(
            id: _studyBase + day,
            title: 'Time to study!',
            body: 'A focused 25 minutes today keeps your plan on track.',
            when: study,
          );
        }

        final weekly = _localTime(now, day, 19, 0);
        if (weekly.weekday == DateTime.sunday && weekly.isAfter(now)) {
          await _scheduleOnce(
            id: _weeklyReportId,
            title: 'Your week in StudyTrail',
            body: 'See how this week went against the last, and what to '
                'work on next.',
            when: weekly,
            payload: weeklyReportPayload,
          );
        }

        final risk = _localTime(now, day, 21, 0);
        if (streak > 0 && !skipToday && risk.isAfter(now)) {
          await _scheduleOnce(
            id: _streakBase + day,
            title: day == 0
                ? 'Your $streak-day streak is at risk'
                : 'Keep your streak alive',
            body: 'You haven\'t studied today yet. One task is enough.',
            when: risk,
          );
        }
      }
    } catch (e) {
      debugPrint('Reminder scheduling failed: $e');
    }
  }

  DateTime _localTime(DateTime now, int dayOffset, int hour, int minute) =>
      DateTime(now.year, now.month, now.day + dayOffset, hour, minute);

  Future<void> _cancelReminders() async {
    await _notificationsPlugin.cancel(id: _legacyDailyId);
    await _notificationsPlugin.cancel(id: _weeklyReportId);
    for (var day = 0; day < _daysAhead; day++) {
      await _notificationsPlugin.cancel(id: _studyBase + day);
      await _notificationsPlugin.cancel(id: _streakBase + day);
    }
  }

  Future<void> _scheduleOnce({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
  }) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'daily_reminders',
      'Daily Reminders',
      channelDescription: 'Reminders to keep your study streak alive',
      importance: Importance.high,
      priority: Priority.high,
    );

    await _notificationsPlugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      // The same instant expressed in UTC, since `tz.local` is never set.
      scheduledDate: tz.TZDateTime.from(when.toUtc(), tz.UTC),
      notificationDetails:
          const NotificationDetails(android: androidDetails),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: payload,
    );
  }

  Future<void> cancelAll() async {
    await _notificationsPlugin.cancelAll();
  }
}
