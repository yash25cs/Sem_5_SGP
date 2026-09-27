import '../data/repositories.dart';
import '../models/models.dart';
import 'async_store.dart';

/// Backs the Roadmap screen — milestones with their task checklists, plus the
/// overall percentage shown at the top.
class RoadmapStore extends AsyncStore {
  RoadmapStore({RoadmapRepository? roadmap, GoalRepository? goals})
      : _roadmap = roadmap ?? const RoadmapRepository(),
        _goals = goals ?? const GoalRepository();

  final RoadmapRepository _roadmap;
  final GoalRepository _goals;

  Goal? _goal;
  List<Milestone> _milestones = const [];
  bool _generating = false;
  bool _lastToggleTouchedDailyTask = false;

  Goal? get goal => _goal;
  List<Milestone> get milestones => _milestones;

  /// True when the last successful [toggleTask] flipped a task that was also on
  /// Home's checklist. Home keeps its own copy of that row, and the shell keeps
  /// both tabs alive, so the screen uses this to refresh it.
  bool get lastToggleTouchedDailyTask => _lastToggleTouchedDailyTask;

  /// True only while [generate] is in flight.
  ///
  /// Separate from [busy] because ticking a task is a mutation too: keying the
  /// screen's "writing your plan" notice off `busy` would flash it on every
  /// checkbox.
  bool get generating => _generating;

  bool get isEmpty => loaded && _milestones.isEmpty;

  int get totalTasks =>
      _milestones.fold(0, (sum, m) => sum + m.tasks.length);

  int get doneTasks => _milestones.fold(0, (sum, m) => sum + m.doneCount);

  double get overallProgress =>
      totalTasks == 0 ? 0 : doneTasks / totalTasks;

  Future<void> load() => runLoad(() async {
        _goal = await _goals.getActiveGoal();
        final goalId = _goal?.id;
        _milestones =
            goalId == null ? const [] : await _roadmap.getMilestones(goalId);
      });

  /// Asks the server to write this goal's weekly plan, then reads it back.
  ///
  /// Replaces rather than appends — `generate-roadmap` clears the goal's
  /// existing milestones first, so generating twice doesn't produce two plans.
  /// That is also why the screen confirms before calling this: a student who has
  /// ticked half of week two loses those ticks.
  ///
  /// Reloads inside the mutation rather than calling [load], so the screen shows
  /// its existing roadmap dimmed under a busy button instead of dropping back to
  /// a skeleton.
  Future<bool> generate() async {
    final goalId = _goal?.id;
    if (goalId == null) {
      setError('Set a study goal first, then generate a roadmap.');
      return false;
    }
    _generating = true;
    notifyListeners();
    try {
      return await runMutation(() async {
        await _roadmap.generateRoadmap(goalId);
        _milestones = await _roadmap.getMilestones(goalId);
        // `roadmap_days` and `current_day` are written by the same function, and
        // the header reads them.
        _goal = await _goals.getActiveGoal();
      });
    } finally {
      _generating = false;
      notifyListeners();
    }
  }

  /// Optimistic checkbox flip. On success the milestone's derived state
  /// (upcoming / active / done) comes back from the repository.
  ///
  /// A task the student also scheduled on Home is ticked through
  /// `complete_task`, so this is a route to XP as well — see
  /// [RoadmapRepository.toggleTask].
  Future<void> toggleTask(Milestone milestone, MilestoneTask task) async {
    final next = !task.done;
    final before = _milestones;
    _lastToggleTouchedDailyTask = false;

    _milestones = [
      for (final m in _milestones)
        m.id != milestone.id
            ? m
            : m.copyWith(
                tasks: [
                  for (final t in m.tasks)
                    t.id == task.id ? t.copyWith(done: next) : t,
                ],
              ),
    ];
    notifyListeners();

    final ok = await runMutation(() async {
      final outcome = await _roadmap.toggleTask(milestone.id, task.id, next);
      _lastToggleTouchedDailyTask = outcome.touchedDailyTask;
      _milestones = [
        for (final m in _milestones)
          m.id == milestone.id ? m.copyWith(state: outcome.state) : m,
      ];
    });

    if (!ok) {
      _milestones = before;
      notifyListeners();
      return;
    }

    // Deliberately outside the mutation. The checkbox is already saved by this
    // point, so letting a failed recompute fail the whole call would revert the
    // tick in the UI while the database keeps it — the screen would then lie
    // until the next load. `overallProgress` is derived locally anyway; the RPC
    // only persists `goals.overall_percent` for the goal_crusher badge.
    final goalId = _goal?.id;
    if (goalId != null) {
      try {
        await _roadmap.recomputeGoalProgress(goalId);
      } catch (_) {
        // Stale by one tick until the next toggle or load recomputes it.
      }
    }
  }
}
