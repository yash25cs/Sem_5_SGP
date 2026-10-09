import '../../models/models.dart';
import '../supabase_client.dart';

/// Aggregates for the Progress screen — study time, accuracy, and the
/// per-subject breakdown. Reads only; every number here is derived from rows
/// the other repositories write.
class AnalyticsRepository {
  const AnalyticsRepository();

  /// Headline tiles: minutes studied, tasks done, and XP earned over [days].
  Future<StudyTotals> getTotals({int days = 7}) async {
    final cutoff = DateTime.now().subtract(Duration(days: days - 1));
    final rows = await db
        .from('activity_log')
        .select()
        .gte('activity_date', _dateOnly(cutoff));

    var minutes = 0, tasks = 0, xp = 0, activeDays = 0;
    for (final r in rows) {
      final day = ActivityDay.fromMap(r);
      minutes += day.minutesStudied;
      tasks += day.tasksCompleted;
      xp += day.xpEarned;
      if (day.isActive) activeDays++;
    }
    return StudyTotals(
      minutes: minutes,
      tasksCompleted: tasks,
      xpEarned: xp,
      activeDays: activeDays,
      windowDays: days,
    );
  }

  /// Minutes per day for the last 7 days, Monday-first, zero-filled so the
  /// bar chart always has exactly 7 bars.
  Future<List<ActivityDay>> getWeeklyBars() async {
    final today = DateTime.now();
    final monday = DateTime(today.year, today.month, today.day)
        .subtract(Duration(days: today.weekday - 1));

    final rows = await db
        .from('activity_log')
        .select()
        .gte('activity_date', _dateOnly(monday));

    final byDate = {
      for (final r in rows)
        _dateOnly(ActivityDay.fromMap(r).date): ActivityDay.fromMap(r),
    };

    return List.generate(7, (i) {
      final d = monday.add(Duration(days: i));
      return byDate[_dateOnly(d)] ?? ActivityDay(date: d);
    });
  }

  /// Per-subject progress and quiz accuracy, straight off `subjects`.
  Future<List<Subject>> getSubjectBreakdown() async {
    final rows = await db
        .from('subjects')
        .select()
        .order('is_focus', ascending: false)
        .order('name', ascending: true);
    return rows.map(Subject.fromMap).toList();
  }

  /// Overall quiz accuracy across completed attempts, 0–1.
  Future<double> getQuizAccuracy() async {
    final rows = await db
        .from('quiz_attempts')
        .select('score, total')
        .not('completed_at', 'is', null);

    var score = 0, total = 0;
    for (final r in rows) {
      score += (r['score'] as num?)?.toInt() ?? 0;
      total += (r['total'] as num?)?.toInt() ?? 0;
    }
    return total == 0 ? 0 : score / total;
  }

  /// How the student's written answers have been marked — all kept attempts,
  /// split by theory and NEP case questions.
  Future<AnswerStats> getAnswerStats() async {
    final rows = await db
        .from('answer_attempts')
        .select('score, max_marks, kind')
        .order('created_at', ascending: false)
        .limit(200);

    final theory = _Tally(), nep = _Tally();
    for (final r in rows) {
      final max = (r['max_marks'] as num?)?.toDouble() ?? 0;
      if (max <= 0) continue;
      final score = (r['score'] as num?)?.toDouble() ?? 0;
      (r['kind'] == 'nep' ? nep : theory).add(score / max);
    }
    return AnswerStats(
      theoryCount: theory.count,
      theoryAverage: theory.average,
      nepCount: nep.count,
      nepAverage: nep.average,
    );
  }

  static String _dateOnly(DateTime d) =>
      DateTime(d.year, d.month, d.day).toIso8601String().split('T').first;
}

class _Tally {
  int count = 0;
  double _sum = 0;
  void add(double fraction) {
    count++;
    _sum += fraction;
  }

  double get average => count == 0 ? 0 : _sum / count;
}

/// Average marks (0–1) on written answers, per kind of question.
class AnswerStats {
  const AnswerStats({
    this.theoryCount = 0,
    this.theoryAverage = 0,
    this.nepCount = 0,
    this.nepAverage = 0,
  });

  final int theoryCount;
  final double theoryAverage;
  final int nepCount;
  final double nepAverage;

  int get total => theoryCount + nepCount;

  /// Across both kinds, weighted by how many of each.
  double get average => total == 0
      ? 0
      : (theoryAverage * theoryCount + nepAverage * nepCount) / total;
}

/// Rolled-up numbers behind the Progress stat tiles.
class StudyTotals {
  const StudyTotals({
    this.minutes = 0,
    this.tasksCompleted = 0,
    this.xpEarned = 0,
    this.activeDays = 0,
    this.windowDays = 7,
  });

  final int minutes;
  final int tasksCompleted;
  final int xpEarned;
  final int activeDays;
  final int windowDays;

  /// "12h 30m" / "45m" for the study-time tile.
  String get studyTimeLabel {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return h == 0 ? '${m}m' : (m == 0 ? '${h}h' : '${h}h ${m}m');
  }

  double get avgMinutesPerDay => windowDays == 0 ? 0 : minutes / windowDays;
}
