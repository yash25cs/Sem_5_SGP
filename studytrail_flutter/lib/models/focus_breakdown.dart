import 'gamification.dart';
import 'plan.dart';
import 'profile.dart';

/// A stretch of the day, for "when do you focus best".
enum DayPart {
  morning('Mornings', '5 am–12 pm'),
  afternoon('Afternoons', '12–5 pm'),
  evening('Evenings', '5–9 pm'),
  night('Late nights', '9 pm–5 am');

  const DayPart(this.label, this.hours);
  final String label;
  final String hours;

  static DayPart of(int hour) => switch (hour) {
        >= 5 && < 12 => DayPart.morning,
        >= 12 && < 17 => DayPart.afternoon,
        >= 17 && < 21 => DayPart.evening,
        _ => DayPart.night,
      };
}

/// Where the last [days] days of focus blocks went: by subject, by goal, and
/// by time of day — and which open goal has had none this week.
class FocusBreakdown {
  const FocusBreakdown({
    this.days = 30,
    this.totalMinutes = 0,
    this.bySubject = const [],
    this.byGoal = const [],
    this.byPart = const {},
    this.quietGoals = const [],
  });

  final int days;
  final int totalMinutes;

  /// Most first. Blocks with no subject picked are "No subject".
  final List<(String, int)> bySubject;

  /// Most first; only goals with time on them.
  final List<(String, int)> byGoal;

  /// Minutes per part of the day, from blocks that know when they started.
  final Map<DayPart, int> byPart;

  /// Open goals with nothing focused on them in the last 7 days, when the
  /// student has more than one goal on the go.
  final List<String> quietGoals;

  bool get isEmpty => totalMinutes == 0;

  /// The part of the day with the most focus; null without timing data.
  DayPart? get bestPart {
    if (byPart.isEmpty) return null;
    final best = byPart.entries.reduce((a, b) => b.value > a.value ? b : a);
    return best.value == 0 ? null : best.key;
  }

  /// [bestPart]'s share of the timed minutes, 0–1.
  double get bestShare {
    final best = bestPart;
    if (best == null) return 0;
    final timed = byPart.values.fold(0, (a, b) => a + b);
    return timed == 0 ? 0 : byPart[best]! / timed;
  }

  factory FocusBreakdown.from(
    List<StudySession> sessions,
    List<Subject> subjects,
    List<Goal> goals,
    DateTime now, {
    int days = 30,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final from = today.subtract(Duration(days: days - 1));
    final weekFrom = today.subtract(const Duration(days: 6));
    final subjectById = {for (final s in subjects) s.id: s};
    final goalById = {for (final g in goals) g.id: g};

    var total = 0;
    final bySubject = <String, int>{};
    final byGoal = <String, int>{};
    final byPart = <DayPart, int>{};
    final goalsThisWeek = <String>{};

    for (final s in sessions) {
      final d =
          DateTime(s.sessionDate.year, s.sessionDate.month, s.sessionDate.day);
      if (d.isBefore(from) || d.isAfter(today)) continue;
      final minutes = s.minutes;
      if (minutes <= 0) continue;
      total += minutes;

      final subject = subjectById[s.subjectId];
      final name = subject?.name ?? s.subjectName ?? 'No subject';
      bySubject[name] = (bySubject[name] ?? 0) + minutes;

      final goal = goalById[subject?.goalId];
      if (goal != null) {
        byGoal[goal.name] = (byGoal[goal.name] ?? 0) + minutes;
        if (!d.isBefore(weekFrom)) goalsThisWeek.add(goal.id);
      }

      if (s.startedAt case final at?) {
        final part = DayPart.of(at.hour);
        byPart[part] = (byPart[part] ?? 0) + minutes;
      }
    }

    List<(String, int)> ranked(Map<String, int> m) => [
          for (final e in m.entries) (e.key, e.value)
        ]..sort((a, b) => b.$2.compareTo(a.$2));

    final open = [
      for (final g in goals)
        if (!g.examOver) g,
    ];
    return FocusBreakdown(
      days: days,
      totalMinutes: total,
      bySubject: ranked(bySubject),
      byGoal: ranked(byGoal),
      byPart: byPart,
      quietGoals: open.length < 2
          ? const []
          : [
              for (final g in open)
                if (!goalsThisWeek.contains(g.id)) g.name,
            ],
    );
  }
}

/// "6h 20m", "45m".
String focusTimeLabel(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}m';
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}
