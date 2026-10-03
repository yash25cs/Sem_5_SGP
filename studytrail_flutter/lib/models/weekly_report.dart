/// The weekly report (`get_weekly_report`, `0021_study_tools.sql`): the last
/// seven days, today included, against the seven before — in the student's
/// own days, not UTC's.
library;

int _int(Object? v) => (v as num?)?.toInt() ?? 0;

/// Totals for one week.
class WeekTotals {
  const WeekTotals({
    this.minutes = 0,
    this.xp = 0,
    this.tasks = 0,
    this.activeDays = 0,
    this.quizzes = 0,
    this.quizCorrect = 0,
    this.quizTotal = 0,
    this.groupQuizzes = 0,
    this.podiums = 0,
    this.answers = 0,
    this.answerPercent,
  });

  final int minutes;
  final int xp;
  final int tasks;
  final int activeDays;
  final int quizzes;
  final int quizCorrect;
  final int quizTotal;
  final int groupQuizzes;
  final int podiums;
  final int answers;

  /// Average mark on written answers, 0–100; null with none written.
  final int? answerPercent;

  /// Share of quiz questions answered right, 0–1; null with none answered.
  double? get quizAccuracy => quizTotal == 0 ? null : quizCorrect / quizTotal;

  factory WeekTotals.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const WeekTotals();
    return WeekTotals(
      minutes: _int(m['minutes']),
      xp: _int(m['xp']),
      tasks: _int(m['tasks']),
      activeDays: _int(m['active_days']),
      quizzes: _int(m['quizzes']),
      quizCorrect: _int(m['quiz_correct']),
      quizTotal: _int(m['quiz_total']),
      groupQuizzes: _int(m['group_quizzes']),
      podiums: _int(m['podiums']),
      answers: _int(m['answers']),
      answerPercent: (m['answer_percent'] as num?)?.toInt(),
    );
  }
}

class WeekDay {
  const WeekDay({required this.date, this.minutes = 0, this.xp = 0});

  final DateTime date;
  final int minutes;
  final int xp;

  factory WeekDay.fromMap(Map<String, dynamic> m) => WeekDay(
        date: DateTime.parse(m['date'] as String),
        minutes: _int(m['minutes']),
        xp: _int(m['xp']),
      );
}

/// Quiz accuracy on one unit this week, with last week's when there was one.
class UnitAccuracy {
  const UnitAccuracy({
    required this.unitLabel,
    required this.answered,
    required this.correct,
    this.answeredBefore = 0,
    this.correctBefore = 0,
  });

  final String unitLabel;
  final int answered;
  final int correct;
  final int answeredBefore;
  final int correctBefore;

  double get accuracy => answered == 0 ? 0 : correct / answered;
  double? get accuracyBefore =>
      answeredBefore == 0 ? null : correctBefore / answeredBefore;

  factory UnitAccuracy.fromMap(Map<String, dynamic> m) => UnitAccuracy(
        unitLabel: (m['unit_label'] as String?) ?? '',
        answered: _int(m['answered']),
        correct: _int(m['correct']),
        answeredBefore: _int(m['answered_before']),
        correctBefore: _int(m['correct_before']),
      );
}

class WeeklyReport {
  const WeeklyReport({
    required this.from,
    required this.to,
    this.thisWeek = const WeekTotals(),
    this.lastWeek = const WeekTotals(),
    this.days = const [],
    this.units = const [],
    this.streak = 0,
    this.bestStreak = 0,
    this.mistakesDue = 0,
  });

  final DateTime from;
  final DateTime to;
  final WeekTotals thisWeek;
  final WeekTotals lastWeek;

  /// Seven entries, oldest first.
  final List<WeekDay> days;

  /// Weakest first.
  final List<UnitAccuracy> units;
  final int streak;
  final int bestStreak;

  /// Cards in My mistakes due now.
  final int mistakesDue;

  bool get empty =>
      thisWeek.minutes == 0 &&
      thisWeek.xp == 0 &&
      thisWeek.quizzes == 0 &&
      thisWeek.tasks == 0 &&
      thisWeek.answers == 0;

  factory WeeklyReport.fromMap(Map<String, dynamic> m) {
    final streak = m['streak'] is Map
        ? Map<String, dynamic>.from(m['streak'] as Map)
        : const <String, dynamic>{};
    Map<String, dynamic>? map(Object? v) =>
        v is Map ? Map<String, dynamic>.from(v) : null;
    return WeeklyReport(
      from: DateTime.parse(m['from'] as String),
      to: DateTime.parse(m['to'] as String),
      thisWeek: WeekTotals.fromMap(map(m['this_week'])),
      lastWeek: WeekTotals.fromMap(map(m['last_week'])),
      days: [
        for (final d in (m['days'] as List? ?? const []))
          WeekDay.fromMap(Map<String, dynamic>.from(d as Map)),
      ],
      units: [
        for (final u in (m['units'] as List? ?? const []))
          UnitAccuracy.fromMap(Map<String, dynamic>.from(u as Map)),
      ],
      streak: _int(streak['current']),
      bestStreak: _int(streak['best']),
      mistakesDue: _int(m['mistakes_due']),
    );
  }
}
