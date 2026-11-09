import '../data/repositories.dart';
import '../models/models.dart';
import 'async_store.dart';

/// Backs the Progress screen: stat tiles, the weekly bar chart, per-subject
/// accuracy, and the activity heatmap.
class ProgressStore extends AsyncStore {
  ProgressStore({
    AnalyticsRepository? analytics,
    GamificationRepository? game,
    GoalRepository? goals,
  })  : _analytics = analytics ?? const AnalyticsRepository(),
        _game = game ?? const GamificationRepository(),
        _goals = goals ?? const GoalRepository();

  final AnalyticsRepository _analytics;
  final GamificationRepository _game;
  final GoalRepository _goals;

  FocusBreakdown _focus = const FocusBreakdown();

  /// Where the last 30 days of focus blocks went.
  FocusBreakdown get focus => _focus;

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
        _focus = await _loadFocus();
      });

  /// An extra on this screen: a failed read leaves the section empty rather
  /// than failing the whole page.
  Future<FocusBreakdown> _loadFocus() async {
    try {
      final all = await Future.wait<Object>([
        _game.getStudySessions(limit: 500),
        _goals.getAllSubjects(),
        _goals.getGoals(),
      ]);
      return FocusBreakdown.from(
        all[0] as List<StudySession>,
        all[1] as List<Subject>,
        all[2] as List<Goal>,
        DateTime.now(),
      );
    } catch (_) {
      return const FocusBreakdown();
    }
  }
}
