import '../data/repositories.dart';
import '../models/models.dart';
import 'async_store.dart';

/// Backs the Progress screen: stat tiles, the weekly bar chart, per-subject
/// accuracy, and the activity heatmap.
class ProgressStore extends AsyncStore {
  ProgressStore({
    AnalyticsRepository? analytics,
    GamificationRepository? game,
  })  : _analytics = analytics ?? const AnalyticsRepository(),
        _game = game ?? const GamificationRepository();

  final AnalyticsRepository _analytics;
  final GamificationRepository _game;

  StudyTotals _totals = const StudyTotals();
  List<ActivityDay> _weekly = const [];
  List<ActivityDay> _heatmap = const [];
  List<Subject> _subjects = const [];
  Streak _streak = const Streak();
  double _quizAccuracy = 0;
  AnswerStats _answers = const AnswerStats();

  /// How written answers (theory and NEP) have been marked.
  AnswerStats get answers => _answers;

  StudyTotals get totals => _totals;

  /// Exactly 7 entries, Monday-first, zero-filled.
  List<ActivityDay> get weekly => _weekly;

  /// Last 60 days for the heatmap grid.
  List<ActivityDay> get heatmap => _heatmap;

  List<Subject> get subjects => _subjects;
  Streak get streak => _streak;

  /// 0–1 across all completed quiz attempts.
  double get quizAccuracy => _quizAccuracy;

  /// Tallest bar in the week, used to scale the chart. Floored at 1 so an
  /// all-zero week doesn't divide by zero.
  int get weeklyPeak => _weekly.fold(
        1,
        (peak, d) => d.minutesStudied > peak ? d.minutesStudied : peak,
      );

  Future<void> load() => runLoad(() async {
        final results = await Future.wait([
          _analytics.getTotals(),
          _analytics.getWeeklyBars(),
          _analytics.getSubjectBreakdown(),
          _analytics.getQuizAccuracy(),
          _game.getRecentActivity(),
          _game.getStreak(),
          _analytics.getAnswerStats(),
        ]);
        _totals = results[0] as StudyTotals;
        _weekly = results[1] as List<ActivityDay>;
        _subjects = results[2] as List<Subject>;
        _quizAccuracy = results[3] as double;
        _heatmap = results[4] as List<ActivityDay>;
        _streak = results[5] as Streak;
        _answers = results[6] as AnswerStats;
      });
}
