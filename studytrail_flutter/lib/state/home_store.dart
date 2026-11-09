import 'dart:io';

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

  /// Every open goal has a paper within [HomeStore.finalStretchDays]: no new
  /// topics now, only revision.
  revising,

  /// The write failed; [HomeStore.error] says why.
  failed,
}

/// A paper close enough that Home stops handing out new topics and switches
/// to revision: weak spots, due cards, the most-asked units, a revision sheet
/// and an early night.
class FinalStretch {
  const FinalStretch({
    required this.paper,
    required this.goal,
    this.subject,
    required this.days,
  });

  /// The subject's name, or the goal's when it has no dated papers.
  final String paper;
  final Goal goal;
  final Subject? subject;

  /// 0 = today.
  final int days;

  String get when => switch (days) {
        0 => 'today',
        1 => 'tomorrow',
        _ => 'in $days days',
      };
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
    MaterialRepository? materials,
    FlashcardRepository? cards,
    ExamPaperRepository? papers,
  })  : _cards = cards ?? const FlashcardRepository(),
        _papers = papers ?? const ExamPaperRepository(),
        _profiles = profiles ?? const ProfileRepository(),
        _goals = goals ?? const GoalRepository(),
        _tasks = tasks ?? const TaskRepository(),
        _game = game ?? const GamificationRepository(),
        _roadmap = roadmap ?? const RoadmapRepository(),
        _materials = materials ?? const MaterialRepository();

  /// How many roadmap tasks one day's plan pulls in at a time. Roughly a
  /// milestone's worth — the generator writes about four tasks a week.
  static const plannedTasksPerDay = 4;

  final ProfileRepository _profiles;
  final GoalRepository _goals;
  final TaskRepository _tasks;
  final GamificationRepository _game;
  final RoadmapRepository _roadmap;
  final MaterialRepository _materials;
  final FlashcardRepository _cards;
  final ExamPaperRepository _papers;

  /// How close a paper must be for the final stretch.
  static const finalStretchDays = 2;

  Profile? _profile;
  Goal? _goal;
  List<Goal> _allGoals = const [];
  Streak _streak = const Streak();
  List<DailyTask> _tasksToday = const [];
  List<Subject> _subjects = const [];

  /// Every goal's subjects — [_subjects] is only the selected goal's.
  List<Subject> _allSubjects = const [];
  int _plannedCount = 0;
  String? _plannedFrom;
  RoadmapPace? _pace;
  Map<String, GoalResult> _results = const {};
  int _dueCards = 0;
  List<ExamTopic> _askedMost = const [];
  int? _goalFocusMinutes;
  Map<String, StudyMaterial> _syllabi = const {};
  String? _readingSyllabusFor;

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

  /// Every exam the selected goal has a date for is behind the student: the
  /// goal's own and each subject's paper. The test the widgets use
  /// (`WidgetData.kt`), so Home says "finished" when the home screen does,
  /// and stops offering a catch-up for an exam that's been sat. Planning and
  /// weak spots go only once every goal is over ([openGoals]).
  bool get examsOver {
    final goal = _goal;
    return goal != null && goalOver(goal);
  }

  /// [goal]'s exams are all behind the student: its own date and every
  /// subject paper it has, as [examsOver] says for the selected goal.
  bool goalOver(Goal goal) {
    if (goal.daysLeft != null) return false; // today or still ahead
    final papers = [
      for (final s in _subjectsOf(goal)) ?s.daysUntilExam(),
    ];
    if (papers.any((d) => d >= 0)) return false;
    return goal.examOver || papers.isNotEmpty;
  }

  /// The selected goal's subjects come from their own query; the others'
  /// from [_allSubjects].
  List<Subject> _subjectsOf(Goal goal) => goal.id == _goal?.id
      ? _subjects
      : [
          for (final s in _allSubjects)
            if (s.goalId == goal.id) s,
        ];

  /// Goals still being worked towards, newest first. Each one's tasks count
  /// on today's list and in reminders, whichever is selected.
  List<Goal> get openGoals => [
        for (final g in _allGoals)
          if (!goalOver(g)) g,
      ];

  /// Another goal still to work on, for a finished goal's card to point at.
  Goal? get nextOpenGoal =>
      openGoals.where((g) => g.id != _goal?.id).firstOrNull;

  /// The soonest paper of an open goal within [finalStretchDays], if any.
  FinalStretch? get finalStretch {
    FinalStretch? best;
    for (final g in openGoals) {
      for (final s in _stretchesOf(g)) {
        if (best == null || s.days < best.days) best = s;
      }
    }
    return best;
  }

  /// [goal] has a paper within [finalStretchDays]: no new topics for it.
  bool inFinalStretch(Goal goal) =>
      !goalOver(goal) && _stretchesOf(goal).isNotEmpty;

  List<FinalStretch> _stretchesOf(Goal goal) {
    bool near(int? d) => d != null && d >= 0 && d <= finalStretchDays;
    final dated = [
      for (final s in _subjectsOf(goal))
        if (s.examDate != null) s,
    ];
    if (dated.isEmpty) {
      return [
        if (near(goal.daysLeft))
          FinalStretch(paper: goal.name, goal: goal, days: goal.daysLeft!),
      ];
    }
    return [
      for (final s in dated)
        if (near(s.daysUntilExam()))
          FinalStretch(
              paper: s.name, goal: goal, subject: s, days: s.daysUntilExam()!),
    ];
  }

  /// Flashcards due now, for the final stretch.
  int get dueCards => _dueCards;

  /// The units past papers ask most, most first ('Other' left out).
  List<ExamTopic> get askedMost => _askedMost;

  /// How [goal]'s exam went, once the student has said.
  GoalResult? resultOf(Goal goal) => _results[goal.id];

  /// Minutes focused on the selected goal's subjects, once its exams are
  /// over — set against the result. Null before it's known.
  int? get goalFocusMinutes => _goalFocusMinutes;

  /// Saves how a goal's exam went.
  Future<bool> saveResult(GoalResult result) => runMutation(() async {
        final saved = await _goals.saveResult(result);
        _results = {..._results, saved.goalId: saved};
      });

  /// The goal a task on today's list belongs to, named only when there's
  /// more than one goal on the go — with one, it goes without saying.
  String? goalNameOf(DailyTask task) {
    if (openGoals.length < 2) return null;
    return _allGoals.where((g) => g.id == task.goalId).firstOrNull?.name;
  }

  /// Dates one subject's exam, then reloads so a pushed-out goal date and the
  /// pace banner reflect it.
  Future<bool> setSubjectExamDate(Subject subject, DateTime? date) async {
    final ok = await runMutation(
        () => _goals.setSubjectExamDate(subject.id, date));
    if (ok) await load();
    return ok;
  }

  int get doneCount => _tasksToday.where((t) => t.done).length;

  /// How many tasks the last [planDayFromRoadmap] scheduled, and the milestone
  /// they came from — so the screen can name the week it just planned.
  int get plannedCount => _plannedCount;
  String? get plannedFrom => _plannedFrom;

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

  /// Hands the home-screen widgets every exam date, the streak, and today's
  /// tasks. All the subject dates, not just the next: the countdown moves on
  /// to the following paper by itself after each exam day. Every goal's
  /// papers, not just the selected one's — a student keeping two goals sits
  /// both sets.
  void _syncWidget() {
    final goal = _goal;
    HomeWidgetSync.push(
      goalName: goal?.name,
      goalDate: goal?.examDate,
      subjectExams: [
        for (final g in _allGoals)
          // A goal without dated papers counts by its own date.
          if (_subjectsOf(g).any((s) => s.examDate != null))
            for (final s in _subjectsOf(g)) (s.name, s.examDate)
          else
            (g.name, g.examDate),
      ],
      streak: _streak.currentStreak,
      bestStreak: _streak.bestStreak,
      lastStudied: _streak.lastActiveDate,
      tasksDone: doneCount,
      tasksTotal: _tasksToday.length,
      nextTasks: [
        for (final t in _tasksToday)
          if (!t.done) t.title,
      ],
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
      _allSubjects = const [];
      _pace = null;
      _syllabi = const {};
      _results = const {};
    } else {
      final more = await Future.wait<Object?>([
        _goals.getSubjects(goalId),
        _loadPace(goalId),
        // An extra like pace: a failed read just shows "Add syllabus".
        _materials
            .getSyllabi()
            .catchError((Object _) => _syllabi),
        // Also an extra: without it the other goals count by their own date.
        _goals
            .getAllSubjects()
            .catchError((Object _) => const <Subject>[]),
        // Extra too, and absent before 0037.
        _goals
            .getResults()
            .catchError((Object _) => const <String, GoalResult>{}),
      ]);
      _subjects = more[0] as List<Subject>;
      _pace = more[1] as RoadmapPace?;
      _syllabi = more[2] as Map<String, StudyMaterial>;
      _allSubjects = more[3] as List<Subject>;
      _results = more[4] as Map<String, GoalResult>;
    }
    await _loadExtras();
  }

  /// What only some states show: the final stretch's due cards and
  /// most-asked units, and a finished goal's focused time. Extras all — a
  /// failed read just leaves them out.
  Future<void> _loadExtras() async {
    final stretch = finalStretch != null;
    final finished = examsOver;
    final ids = {for (final s in _subjects) s.id};
    final got = await Future.wait<Object?>([
      stretch
          ? _cards
              .getDueCards(limit: 100)
              .then<Object?>((c) => c.length)
              .catchError((Object _) => 0)
          : Future.value(0),
      stretch
          ? _papers
              .getTopics()
              .then<Object?>((t) => t)
              .catchError((Object _) => const <ExamTopic>[])
          : Future.value(const <ExamTopic>[]),
      finished && ids.isNotEmpty
          ? _game
              .getStudySessions(limit: 500)
              .then<Object?>((all) => all
                  .where((s) => ids.contains(s.subjectId))
                  .fold<int>(0, (sum, s) => sum + s.minutes))
              .catchError((Object _) => null)
          : Future<Object?>.value(),
    ]);
    _dueCards = got[0] as int;
    _askedMost = [
      for (final t in got[1] as List<ExamTopic>)
        if (!t.isOther) t,
    ]..sort((a, b) => b.timesAsked.compareTo(a.timesAsked));
    _goalFocusMinutes = got[2] as int?;
  }

  /// [subject]'s syllabus, if it has one (`0027`).
  StudyMaterial? syllabusOf(Subject subject) => _syllabi[subject.id];

  /// The subject whose syllabus is being uploaded and read right now.
  String? get readingSyllabusFor => _readingSyllabusFor;

  /// Adds — or replaces — [subject]'s syllabus from a PDF, and has it read.
  Future<bool> addSyllabusFile(Subject subject, File file, String fileName) =>
      _addSyllabus(
          subject,
          () => _materials.uploadFile(
                file: file,
                fileName: fileName,
                goalId: _goal?.id,
                subjectId: subject.id,
              ));

  /// Adds — or replaces — [subject]'s syllabus from typed or pasted text.
  Future<bool> addSyllabusText(Subject subject, String text) => _addSyllabus(
      subject,
      () => _materials.addSyllabusText(
            subjectId: subject.id,
            title: '${subject.name} syllabus',
            text: text.trim(),
            goalId: _goal?.id,
          ));

  /// Uploads, then waits for `embed-material` to read it: a syllabus is only
  /// any use once its units are in. One that can't be read is taken back out
  /// and any earlier syllabus stays; the earlier one is removed only once the
  /// new one has been read.
  Future<bool> _addSyllabus(
      Subject subject, Future<StudyMaterial> Function() create) async {
    final previous = _syllabi[subject.id];
    _readingSyllabusFor = subject.id;
    final ok = await runMutation(() async {
      final added = await create();
      try {
        await _materials.requestIngest(added.id);
      } catch (_) {
        try {
          await _materials.deleteMaterial(added);
        } catch (_) {
          // The read failure is the error worth showing.
        }
        rethrow;
      }
      if (previous != null) {
        try {
          await _materials.deleteMaterial(previous);
        } catch (_) {
          // Left in the library; the newer one is what counts.
        }
      }
      _syllabi = await _materials.getSyllabi();
    });
    _readingSyllabusFor = null;
    notifyListeners();
    return ok;
  }

  /// Removes [subject]'s syllabus, file and all.
  Future<bool> removeSyllabus(Subject subject) async {
    final current = _syllabi[subject.id];
    if (current == null) return true;
    return runMutation(() async {
      await _materials.deleteMaterial(current);
      _syllabi = {
        for (final e in _syllabi.entries)
          if (e.key != subject.id) e.key: e.value,
      };
    });
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
        // The streak widget stops its "study today" glow.
        _syncWidget();
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
    // The task's own goal: with two on the go it may not be the selected one.
    final goalId = task.goalId ?? _goal?.id;
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

  /// Fills today's checklist from the next unfinished stretch of the roadmap.
  ///
  /// Without this the generated roadmap sat one tab away and Home stayed empty:
  /// `daily_tasks` rows were only ever added by hand. Each seeded row carries its
  /// `milestone_task_id`, which is what makes `complete_task` tick the roadmap
  /// checkbox in the same transaction — one tick, both screens.
  ///
  /// Takes one milestone at a time rather than the whole plan, so a 7-week
  /// roadmap doesn't land on today as 28 tasks, and skips anything already
  /// scheduled on any date so a second tap can't duplicate a topic.
  ///
  /// Plans every open goal, the selected one first: a student keeping two
  /// goals has both to finish, so switching between them mustn't decide
  /// which one gets studied. A goal whose exams are over gets nothing.
  Future<PlanDayResult> planDayFromRoadmap({
    int limit = plannedTasksPerDay,
  }) async {
    final open = [
      ...openGoals.where((g) => g.id == _goal?.id),
      ...openGoals.where((g) => g.id != _goal?.id),
    ];
    if (open.isEmpty) return PlanDayResult.noRoadmap;
    // A goal with a paper in the next two days gets revision, not new topics.
    final goals = open.where((g) => !inFinalStretch(g)).toList();
    if (goals.isEmpty) return PlanDayResult.revising;

    _plannedCount = 0;
    _plannedFrom = null;
    var hasRoadmap = false;
    final from = <String>[];

    final ok = await runMutation(() async {
      for (final goal in goals) {
        final milestones = await _roadmap.getMilestones(goal.id);
        if (milestones.isEmpty) continue;
        hasRoadmap = true;

        final scheduled = await _tasks.getScheduledMilestoneTaskIds(goal.id);

        for (final milestone in milestones) {
          final next = milestone.tasks
              .where((t) => !t.done && !scheduled.contains(t.id))
              .take(limit)
              .toList();
          if (next.isEmpty) continue;

          final created = await _tasks.createTasksFromRoadmap(
            goalId: goal.id,
            tasks: next,
          );
          _tasksToday = [..._tasksToday, ...created];
          _plannedCount += created.length;
          final week = milestone.weekLabel ?? milestone.title;
          from.add(goals.length > 1 ? '${goal.name} ($week)' : week);
          break;
        }
      }
      _plannedFrom = from.isEmpty ? null : from.join(' and ');
    });

    if (!ok) return PlanDayResult.failed;
    if (_plannedCount > 0) return PlanDayResult.added;
    if (goals.length < open.length) return PlanDayResult.revising;
    return hasRoadmap ? PlanDayResult.nothingLeft : PlanDayResult.noRoadmap;
  }

  Future<bool> deleteTask(DailyTask task) => runMutation(() async {
        await _tasks.deleteTask(task.id);
        _tasksToday = _tasksToday.where((t) => t.id != task.id).toList();
      });
}
