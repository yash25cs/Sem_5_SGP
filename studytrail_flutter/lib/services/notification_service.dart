import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// The last ten years of rules, not all of history: reminders only ever look a
// week ahead, and the full database took 8x as long to load before the first
// frame (56 ms against 7 ms on a desktop, measured 2026-10-04).
import 'package:timezone/data/latest_10y.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Local, on-device reminders. Nothing here talks to a server: what to
/// schedule is decided by `ReminderSync`, which reads the student's streak.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  /// For tests: a stand-in that overrides what it needs, so nothing reaches
  /// the platform plugin.
  @visibleForTesting
  NotificationService.forTesting();

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

  /// The ongoing "focus session running" notice. Shown and cleared by
  /// `PomodoroStore`; never scheduled, so [_cancelReminders] leaves it alone.
  static const int _focusSessionId = 400;
  static const String focusSessionPayload = 'focus_session';

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
      // A focus notice can only outlive its session if the process was killed
      // mid-block, and the timer died with it.
      await _notificationsPlugin.cancel(id: _focusSessionId);
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

  /// Shows (or updates) the ongoing notice for a focus block in progress.
  ///
  /// Ongoing and not auto-cancelled, so it can't be swiped away while the
  /// block runs — except on Android 14+, where the system lets the student
  /// dismiss any ongoing notification; the next pause or resume puts it back.
  /// With [endsAt] the notice counts down on its own; without it (paused) it
  /// shows [body] as is.
  ///
  /// Never throws: the session must not fail over a notification.
  Future<void> showFocusSession({
    required String title,
    required String body,
    DateTime? endsAt,
  }) async {
    try {
      final details = AndroidNotificationDetails(
        'focus_session',
        'Focus session',
        channelDescription: 'Shows while a focus block is running',
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        autoCancel: false,
        onlyAlertOnce: true,
        playSound: false,
        enableVibration: false,
        category: AndroidNotificationCategory.progress,
        showWhen: endsAt != null,
        when: endsAt?.millisecondsSinceEpoch,
        usesChronometer: endsAt != null,
        chronometerCountDown: endsAt != null,
      );
      await _notificationsPlugin.show(
        id: _focusSessionId,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(android: details),
        payload: focusSessionPayload,
      );
    } catch (e) {
      debugPrint('Focus notice failed: $e');
    }
  }

  Future<void> cancelFocusSession() async {
    try {
      await _notificationsPlugin.cancel(id: _focusSessionId);
    } catch (e) {
      debugPrint('Focus notice cancel failed: $e');
    }
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
    int studyMinute = 18 * 60,
  }) async {
    final (riskHour, riskMinute) = streakReminderTime(studyMinute);
    try {
      await _cancelReminders();
      if (!enabled) return;
      if (askPermission) await requestPermissions();

      final now = DateTime.now();
      for (var day = 0; day < _daysAhead; day++) {
        final skipToday = day == 0 && studiedToday;

        final study =
            _localTime(now, day, studyMinute ~/ 60, studyMinute % 60);
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

        final risk = _localTime(now, day, riskHour, riskMinute);
        if (streak > 0 &&
            !skipToday &&
            riskHour >= 0 &&
            risk.isAfter(now)) {
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

  /// The "streak at risk" nudge: 9 PM, or an hour after a study reminder set
  /// later than 8 PM. (-1, -1) when that would run past midnight, since a
  /// nudge for a day that's already over saves nothing.
  static (int, int) streakReminderTime(int studyMinute) {
    final at = studyMinute < 20 * 60 ? 21 * 60 : studyMinute + 60;
    if (at >= 24 * 60) return (-1, -1);
    return (at ~/ 60, at % 60);
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
}
