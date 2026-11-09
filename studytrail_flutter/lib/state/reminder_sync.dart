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
    GoalRepository goals = const GoalRepository(),
  }) async {
    final enabled = await LocalPrefs.remindersEnabled();
    var plan = const ReminderPlan(studiedToday: false, streak: 0);
    var exams = const GoalExams();
    if (enabled) {
      try {
        plan = ReminderPlan.from(await game.getStreak(), DateTime.now());
      } catch (_) {
        // Offline: keep the plain daily reminder, skip the streak one.
      }
      try {
        final all = await Future.wait(
            [goals.getGoals(), goals.getAllSubjects()]);
        exams = GoalExams.from(all[0] as List<Goal>,
            all[1] as List<Subject>, DateTime.now());
      } catch (_) {
        // Offline: no exam-eve reminders this time.
      }
    }
    await NotificationService().scheduleReminders(
      enabled: enabled,
      studiedToday: plan.studiedToday,
      streak: plan.streak,
      askPermission: askPermission,
      studyMinute: await LocalPrefs.reminderMinute(),
      goalNames: exams.openGoals,
      exams: exams.upcoming,
    );
  }
}

/// Every goal's exams, for reminders that cover all of them rather than the
/// one selected on Home.
@immutable
class GoalExams {
  const GoalExams({this.openGoals = const [], this.upcoming = const []});

  /// Names of the goals still on the go: an exam ahead, or no date yet.
  final List<String> openGoals;

  /// Papers from today on, soonest first: a goal's dated subjects, or its
  /// own date when none of them has one.
  final List<(String, DateTime)> upcoming;

  factory GoalExams.from(
      List<Goal> goals, List<Subject> subjects, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    bool ahead(DateTime d) =>
        !DateTime(d.year, d.month, d.day).isBefore(today);

    final open = <String>[];
    final upcoming = <(String, DateTime)>[];
    for (final g in goals) {
      final dated = [
        for (final s in subjects)
          if (s.goalId == g.id && s.examDate != null) (s.name, s.examDate!),
      ];
      final papers = dated.isNotEmpty
          ? dated
          : [if (g.examDate != null) (g.name, g.examDate!)];
      final left = papers.where((e) => ahead(e.$2)).toList();
      if (papers.isEmpty || left.isNotEmpty) open.add(g.name);
      upcoming.addAll(left);
    }
    upcoming.sort((a, b) => a.$2.compareTo(b.$2));
    return GoalExams(openGoals: open, upcoming: upcoming);
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
