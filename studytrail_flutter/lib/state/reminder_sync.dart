import 'package:flutter/foundation.dart';

import '../data/local_prefs.dart';
import '../data/repositories.dart';
import '../models/models.dart';
import '../services/notification_service.dart';

/// Decides which reminders the week ahead needs and hands them to
/// [NotificationService].
///
/// Run when the app opens, when it comes back to the foreground, and when it
/// goes to the background — the last one is what catches studying done in this
/// session, so today's 6 PM nudge doesn't arrive after the work is done.
class ReminderSync {
  const ReminderSync._();

  static Future<void> run({
    bool askPermission = false,
    GamificationRepository game = const GamificationRepository(),
  }) async {
    final enabled = await LocalPrefs.remindersEnabled();
    var plan = const ReminderPlan(studiedToday: false, streak: 0);
    if (enabled) {
      try {
        plan = ReminderPlan.from(await game.getStreak(), DateTime.now());
      } catch (_) {
        // Offline: keep the plain daily reminder, skip the streak one.
      }
    }
    await NotificationService().scheduleReminders(
      enabled: enabled,
      studiedToday: plan.studiedToday,
      streak: plan.streak,
      askPermission: askPermission,
    );
  }
}

/// What the reminders should say, worked out from the streak row alone.
@immutable
class ReminderPlan {
  const ReminderPlan({required this.studiedToday, required this.streak});

  final bool studiedToday;

  /// The run a missed day would end; 0 when there's nothing to protect.
  final int streak;

  /// `last_active_date` is a date on the server's UTC clock, so "today" is
  /// compared on that clock too. The 18:00 and 21:00 reminders fall on the
  /// same UTC date in India, so this matches what the student means by today.
  factory ReminderPlan.from(Streak s, DateTime now) {
    final utc = now.toUtc();
    final today = DateTime.utc(utc.year, utc.month, utc.day);
    final last = s.lastActiveDate;
    final lastDay =
        last == null ? null : DateTime.utc(last.year, last.month, last.day);

    final studiedToday = lastDay == today;
    // Still alive only if the last active day was today or yesterday; older
    // than that, the next activity starts a new run (or spends a freeze).
    final alive = lastDay != null &&
        (studiedToday || lastDay == today.subtract(const Duration(days: 1)));
    return ReminderPlan(
      studiedToday: studiedToday,
      streak: alive ? s.currentStreak : 0,
    );
  }
}
