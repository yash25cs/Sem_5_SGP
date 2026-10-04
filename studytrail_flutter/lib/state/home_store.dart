import '../data/repositories.dart';
import '../models/models.dart';
import '../services/home_widget_sync.dart';
import 'async_store.dart';

/// What [HomeStore.planDayFromRoadmap] managed to do, so Home can say something
/// specific instead of a generic failure.
enum PlanDayResult {
  /// Tasks were added to today's list.
  added,

  /// The goal has no roadmap to pull from yet.
  noRoadmap,

  /// Every roadmap task is either done or already scheduled.
  nothingLeft,

  /// The write failed; [HomeStore.error] says why.
  failed,
}

/// Backs the Home screen: greeting, active goal, today's checklist, focus
/// subjects, and the streak chip.
class HomeStore extends AsyncStore {
  HomeStore({
    ProfileRepository? profiles,
    GoalRepository? goals,
    TaskRepository? tasks,
    GamificationRepository? game,
    RoadmapRepository? roadmap,
  })  : _profiles = profiles ?? const ProfileRepository(),
        _goals = goals ?? const GoalRepository(),
        _tasks = tasks ?? const TaskRepository(),
        _game = game ?? const GamificationRepository(),
        _roadmap = roadmap ?? const RoadmapRepository();

  /// How many roadmap tasks one day's plan pulls in at a time. Roughly a
  /// milestone's worth — the generator writes about four tasks a week.
  static const plannedTasksPerDay = 4;

  final ProfileRepository _profiles;
  final GoalRepository _goals;
  final TaskRepository _tasks;
  final GamificationRepository _game;
  final RoadmapRepository _roadmap;

  Profile? _profile;
  Goal? _goal;
  List<Goal> _allGoals = const [];
  Streak _streak = const Streak();
  List<DailyTask> _tasksToday = const [];
  List<Subject> _subjects = const [];
  int _plannedCount = 0;
  String? _plannedFrom;
  RoadmapPace? _pace;

  /// Pace against the active goal's roadmap; null before it loads or when the
  /// project predates `0015_catch_up.sql`.
  RoadmapPace? get pace => _pace;

  Profile? get profile => _profile;

  /// The goal every other read on this screen is scoped to.
  Goal? get goal => _goal;

  /// Every goal the student has, newest first — the switcher's list. A student
  /// can keep several (one per exam) but the app works against one at a time.
  List<Goal> get allGoals => _allGoals;

  Streak get streak => _streak;
  List<DailyTask> get tasks => _tasksToday;
  List<Subject> get subjects => _subjects;

  /// The soonest subject exam still ahead (today counts), for the hero card.
  Subject? get nextExam {
    final upcoming = [
      for (final s in _subjects)
        if ((s.daysUntilExam() ?? -1) >= 0) s,
    ]..sort((a, b) => a.examDate!.compareTo(b.examDate!));
    return upcoming.firstOrNull;
  }

  /// Dates one subject's exam, then reloads so a pushed-out goal date and the
  /// pace banner reflect it.
  Future<bool> setSubjectExamDate(Subject subject, DateTime? date) async {
    final ok = await runMutation(
        () => _goals.setSubjectExamDate(subject.id, date));
    if (ok) await load();
    return ok;
  }

  /// Subjects the student marked as focus, for the "Focus areas" row.
  List<Subject> get focusSubjects =>
      _subjects.where((s) => s.isFocus).toList();

  int get doneCount => _tasksToday.where((t) => t.done).length;

  /// How many tasks the last [planDayFromRoadmap] scheduled, and the milestone
  /// they came from — so the screen can name the week it just planned.
  int get plannedCount => _plannedCount;
  String? get plannedFrom => _plannedFrom;

  double get todayProgress =>
      _tasksToday.isEmpty ? 0 : doneCount / _tasksToday.length;

  bool _prefetched = false;

  /// [load], started before Home is on screen — during the launch splash —
  /// so Home opens already filled in.
  Future<void> prefetch() {
    _prefetched = true;
    return load();
  }

  /// True once after [prefetch]: Home's own first load would only repeat it.
  bool takePrefetch() {
    final was = _prefetched;
    _prefetched = false;
    return was;
  }

  Future<void> load() => runLoad(() async {
        await _loadAll();
        _syncWidget();
      });

  /// Hands the home-screen widget the next exam and today's tasks.
  void _syncWidget() {
    final subject = nextExam;
    final goal = _goal;
    final next = _tasksToday.where((t) => !t.done).firstOrNull;
    HomeWidgetSync.push(
      examName: subject?.name ?? goal?.name,
      examDate: subject?.examDate ?? goal?.examDate,
      streak: _streak.currentStreak,
      tasksDone: doneCount,
      tasksTotal: _tasksToday.length,
      nextTask: next?.title,
    ).ignore();
  }

  Future<void> _loadAll() async {
    // Independent reads — run them together rather than five round-trips.
    final results = await Future.wait([
      _profiles.getMyProfile(),
      _goals.getGoals(),
      _tasks.getTodayTasks(),
      _game.getStreak(),
    ]);
    _profile = results[0] as Profile?;
    _allGoals = results[1] as List<Goal>;
    _tasksToday = results[2] as List<DailyTask>;
    _streak = results[3] as Streak;

    // Derived from the full list rather than a separate `getActiveGoal()`
    // round-trip. Same rule as that query: newest active row wins, so a
    // half-finished switch still resolves to one goal.
    _goal = _allGoals.where((g) => g.isActive).firstOrNull;

    // Both need only the goal id, so they go together: one round trip to the
    // Sydney database (~300 ms from India) instead of two.
    final goalId = _goal?.id;
    if (goalId == null) {
      _subjects = const [];
      _pace = null;
    } else {
      final more = await Future.wait<Object?>([
        _goals.getSubjects(goalId),
        _loadPace(goalId),
      ]);
      _subjects = more[0] as List<Subject>;
      _pace = more[1] as RoadmapPace?;
    }
  }

  /// Pace is an extra on this screen, so a failure hides the banner rather
  /// than failing the whole load.
  Future<RoadmapPace?> _loadPace(String goalId) async {
    try {
      return await _roadmap.getPace(goalId);
    } catch (_) {
      return null;
    }
  }

  /// Rebuilds the next week of tasks at the pace the exam needs. Returns what
  /// was done, or null with [error] set.
  Future<CatchUpResult?> catchUp() async {
    final goalId = _goal?.id;
    if (goalId == null) return null;
    CatchUpResult? result;
    final ok = await runMutation(() async {
      result = await _roadmap.planCatchUp(goalId);
      _tasksToday = await _tasks.getTodayTasks();
    });
    if (!ok) return null;
    _pace = await _loadPace(goalId);
    notifyListeners();
    return result;
  }

  /// Switches which goal the app works against, then reloads everything scoped
  /// to it — tasks stay global, but subjects and the hero card follow the goal.
  Future<bool> switchGoal(String goalId) async {
    if (goalId == _goal?.id) return true;
    final ok = await runMutation(() => _goals.setActiveGoal(goalId));
    if (ok) await load();
    return ok;
  }

  Future<void> refresh() async {
    _tasksToday = await _tasks.getTodayTasks();
    notifyListeners();
    _syncWidget();
  }

  /// Flips a checkbox optimistically, then persists. Reverts on failure so the
  /// UI never claims a write succeeded when it didn't.
  ///
  /// Activity, XP, the streak, and any badge it earns are all rolled into the
  /// `complete_task` RPC, so there's nothing to log from here.
  Future<void> toggleTask(DailyTask task) async {
    final next = !task.done;
    final before = _tasksToday;
    _tasksToday = [
      for (final t in _tasksToday)
        t.id == task.id
            ? t.copyWith(done: next, tag: next ? TaskTag.done : TaskTag.now)
            : t,
    ];
    notifyListeners();

    final ok = await runMutation(() async {
      final saved = await _tasks.setDone(task, next);
      _tasksToday = [
        for (final t in _tasksToday) t.id == saved.id ? saved : t,
      ];
    });

    if (!ok) {
      _tasksToday = before;
      notifyListeners();
      return;
    }
    _syncWidget();

    // Everything below is deliberately outside the mutation. The tick is already
    // saved by this point, and this method returns void, so a throw here would
    // surface as an unhandled async error rather than as a failed write.
    if (next) {
      // The RPC rolled the streak forward; re-read it for the header chip.
      try {
        _streak = await _game.getStreak();
        notifyListeners();
      } catch (_) {
        // Header chip stays on the previous count until the next load.
      }
    }

    // A task seeded from the roadmap. `complete_task` already mirrored
    // `milestone_tasks.done` inside its transaction, but the parent milestone's
    // `state` and the goal's stored percentage are both derived elsewhere — the
    // Roadmap tab would show a ticked task under an "upcoming" week, and the hero
    // card's percentage wouldn't move, until something recomputed them.
    final milestoneTaskId = task.milestoneTaskId;
    final goalId = _goal?.id;
    if (milestoneTaskId != null && goalId != null) {
      try {
        await _roadmap.resyncMilestoneForTask(milestoneTaskId);
        await _roadmap.recomputeGoalProgress(goalId);
        _allGoals = await _goals.getGoals();
        _goal = _allGoals.where((g) => g.isActive).firstOrNull;
        notifyListeners();
      } catch (_) {
        // Hero percentage stays a tick behind until the next load.
      }
    }
  }

  Future<bool> addTask({
    required String title,
    String? subjectId,
    int? durationMin,
  }) =>
      runMutation(() async {
        final created = await _tasks.createTask(
          title: title,
          goalId: _goal?.id,
          subjectId: subjectId,
          durationMin: durationMin,
        );
        _tasksToday = [..._tasksToday, created];
      });

  /// Fills today's checklist from the next unfinished stretch of the roadmap.
  ///
  /// Without this the generated roadmap sat one tab away and Home stayed empty:
  /// `daily_tasks` rows only ever came from [addTask]. Each seeded row carries its
  /// `milestone_task_id`, which is what makes `complete_task` tick the roadmap
  /// checkbox in the same transaction — one tick, both screens.
  ///
  /// Takes one milestone at a time rather than the whole plan, so a 7-week
  /// roadmap doesn't land on today as 28 tasks, and skips anything already
  /// scheduled on any date so a second tap can't duplicate a topic.
  Future<PlanDayResult> planDayFromRoadmap({
    int limit = plannedTasksPerDay,
  }) async {
    final goalId = _goal?.id;
    if (goalId == null) return PlanDayResult.noRoadmap;

    _plannedCount = 0;
    _plannedFrom = null;
    var hasRoadmap = false;

    final ok = await runMutation(() async {
      final milestones = await _roadmap.getMilestones(goalId);
      hasRoadmap = milestones.isNotEmpty;
      if (!hasRoadmap) return;

      final scheduled = await _tasks.getScheduledMilestoneTaskIds(goalId);

      for (final milestone in milestones) {
        final next = milestone.tasks
            .where((t) => !t.done && !scheduled.contains(t.id))
            .take(limit)
            .toList();
        if (next.isEmpty) continue;

        final created = await _tasks.createTasksFromRoadmap(
          goalId: goalId,
          tasks: next,
        );
        _tasksToday = [..._tasksToday, ...created];
        _plannedCount = created.length;
        _plannedFrom = milestone.weekLabel ?? milestone.title;
        return;
      }
    });

    if (!ok) return PlanDayResult.failed;
    if (_plannedCount > 0) return PlanDayResult.added;
    return hasRoadmap ? PlanDayResult.nothingLeft : PlanDayResult.noRoadmap;
  }

  Future<bool> deleteTask(DailyTask task) => runMutation(() async {
        await _tasks.deleteTask(task.id);
        _tasksToday = _tasksToday.where((t) => t.id != task.id).toList();
      });
}
