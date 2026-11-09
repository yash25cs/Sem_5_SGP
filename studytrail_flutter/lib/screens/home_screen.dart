import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:confetti/confetti.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../data/repositories.dart';
import '../models/models.dart';
import '../state/stores.dart';
import '../theme/app_theme.dart';
import '../theme/subject_style.dart';
import '../widgets/common.dart';
import '../widgets/working.dart';
import '../widgets/data_states.dart';
import '../widgets/goal_result_sheet.dart';
import '../widgets/notification_bell.dart';
import '../widgets/streak_modal.dart';
import '../widgets/task_done.dart';
import '../widgets/syllabus_sheet.dart';
import 'flashcards_screen.dart';
import 'profile_screen.dart';
import 'revision_sheet_screen.dart';
import 'set_target_screen.dart';

/// Home / dashboard tab — greeting, streak, today's plan, and subject progress.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.onOpenProfile, this.onOpenQuiz});

  final VoidCallback? onOpenProfile;

  /// Switches the shell to the Quiz tab, for a freshly generated quiz.
  final VoidCallback? onOpenQuiz;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late ConfettiController _confetti;
  bool _hasShownStreakModal = false;
  bool _isPlanningDay = false;

  @override
  void initState() {
    super.initState();
    _confetti = ConfettiController(duration: const Duration(seconds: 2));
    // Deferred: the store notifies listeners, which can't happen during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // The launch splash already fetched both (RootFlow); asking again would
      // just repeat it.
      final home = context.read<HomeStore>();
      if (!home.takePrefetch()) home.load();
      final weak = context.read<WeakSpotsStore>();
      if (!weak.loaded && !weak.loading) weak.load();
    });
  }

  Future<void> _catchUp() async {
    final store = context.read<HomeStore>();
    final result = await store.catchUp();
    if (!mounted) return;
    if (result == null) {
      _toast(store.error ?? 'Could not plan that. Try again.');
      return;
    }
    final moved = result.moved == 0
        ? ''
        : ' ${result.moved} missed task${result.moved == 1 ? '' : 's'} '
            'moved to today.';
    _toast('Next 7 days planned at ${result.perDay} a day.$moved');
  }

  static const _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  Future<void> _pickExamDate(Subject subject) async {
    final store = context.read<HomeStore>();
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: subject.examDate ?? now.add(const Duration(days: 14)),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 730)),
      helpText: '${subject.name} exam date',
    );
    if (picked == null || !mounted) return;
    final ok = await store.setSubjectExamDate(subject, picked);
    if (!mounted) return;
    _toast(ok
        ? '${subject.name} exam set for ${picked.day} ${_monthNames[picked.month - 1]}.'
        : store.error ?? 'Could not save that date.');
  }

  /// One tap from "you keep missing Unit 2" to practice on Unit 2.
  Future<void> _practiceWeak({required bool quiz}) async {
    final weak = context.read<WeakSpotsStore>();
    final messenger = ScaffoldMessenger.of(context);
    if (quiz) {
      final id = await weak.practiceQuiz();
      if (!mounted) return;
      if (id == null) {
        _toast(weak.error ?? 'Could not make that quiz.');
        return;
      }
      await context.read<QuizStore>().load();
      messenger.showSnackBar(SnackBar(
        content: const Text('Weak-spots quiz ready.'),
        action: widget.onOpenQuiz == null
            ? null
            : SnackBarAction(label: 'Open', onPressed: widget.onOpenQuiz!),
      ));
    } else {
      final saved = await weak.practiceCards();
      if (!mounted) return;
      if (saved == null) {
        _toast(weak.error ?? 'Could not make those cards.');
        return;
      }
      await context.read<FlashcardStore>().load();
      messenger.showSnackBar(SnackBar(
        content: Text('$saved cards on your weak spots, due now.'),
        persist: false,
        action: SnackBarAction(
          label: 'Review',
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (routeCtx) => FlashcardsScreen(
                onBack: () => Navigator.of(routeCtx).pop()),
          )),
        ),
      ));
    }
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  /// "Good morning" / "afternoon" / "evening" by local clock.
  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning,';
    if (hour < 17) return 'Good afternoon,';
    return 'Good evening,';
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Opens the goal form as a full route, then refreshes whatever was showing.
  ///
  /// The same screen onboarding uses — `create_goal` retires the previous active
  /// goal, so the new one becomes the goal the app works against.
  Future<void> _createGoal() async {
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (routeContext) => SetTargetScreen(
        stepLabel: 'New goal',
        title: 'New study goal',
        onDone: () => Navigator.of(routeContext).pop(),
        onBack: () => Navigator.of(routeContext).pop(),
      ),
    ));
    if (!mounted) return;
    await context.read<HomeStore>().load();
    // Settings reads the same rows from its own store; keep the two in step so
    // switching tabs doesn't show a stale list.
    if (mounted) await context.read<ProfileStore>().reloadGoals();
  }

  /// Due flashcards, straight from the final-stretch card.
  void _openDueCards() => Navigator.of(context).push(MaterialPageRoute(
        builder: (routeCtx) =>
            FlashcardsScreen(onBack: () => Navigator.of(routeCtx).pop()),
      ));

  /// A past paper's most-asked unit: its revision sheet, from whichever of
  /// the student's files has that unit.
  Future<void> _sheetForUnit(String unit) async {
    String? materialId;
    try {
      materialId = await const MaterialRepository().materialForUnit(unit);
    } catch (_) {}
    if (!mounted) return;
    if (materialId == null) {
      _toast('None of your notes has "$unit" as a heading. Pick a file '
          'instead.');
      return;
    }
    await RevisionSheetScreen.open(context,
        materialId: materialId, unitLabel: unit);
  }

  /// "How did it go?" for a finished goal: marks, how it felt, what was
  /// hard. The hard units steer the next goal's roadmap.
  Future<void> _editResult(Goal goal) async {
    final store = context.read<HomeStore>();
    final suggestions = <String>{
      for (final s in store.subjects) s.name,
      for (final t in context.read<WeakSpotsStore>().topics) t.name,
    }.toList();
    final p = context.p;
    final result = await showModalBottomSheet<GoalResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) => GoalResultSheet(
        goal: goal,
        existing: store.resultOf(goal),
        suggestions: suggestions,
      ),
    );
    if (result == null || !mounted) return;
    final ok = await store.saveResult(result);
    if (!mounted) return;
    final hard = result.hardUnits;
    _toast(!ok
        ? store.error ?? 'Could not save that. Try again.'
        : hard.isEmpty
            ? 'Saved.'
            : 'Saved. Your next roadmap will give '
                '${hard.length == 1 ? hard.first : 'those units'} more time.');
  }

  /// Makes [goalId] the selected goal. The Roadmap tab and Settings keep
  /// their own copy of which goal that is, so they're told too.
  Future<void> _switchTo(String goalId) async {
    final store = context.read<HomeStore>();
    final ok = await store.switchGoal(goalId);
    if (!mounted) return;
    if (!ok) {
      _toast(store.error ?? 'Could not switch goal');
      return;
    }
    context.read<RoadmapStore>().load();
    await context.read<ProfileStore>().reloadGoals();
  }

  /// Pulls the next unfinished stretch of the roadmap onto today's list.
  ///
  /// The roadmap generator writes `milestone_tasks`, which live on their own tab;
  /// this is the only thing that turns them into today's work.
  Future<void> _planDay() async {
    setState(() => _isPlanningDay = true);
    try {
      final store = context.read<HomeStore>();
      final result = await store.planDayFromRoadmap();
      if (!mounted) return;
      switch (result) {
        case PlanDayResult.added:
          final count = store.plannedCount;
          final from = store.plannedFrom;
          _toast('Added $count task${count == 1 ? '' : 's'}'
              '${from == null ? '' : ' from $from'}.');
        case PlanDayResult.noRoadmap:
          _toast('Generate a roadmap first — it\'s on the Roadmap tab.');
        case PlanDayResult.nothingLeft:
          _toast('Every roadmap topic is already done or scheduled.');
        case PlanDayResult.revising:
          _toast('Final stretch: no new topics now. Revise with the card '
              'above instead.');
        case PlanDayResult.failed:
          _toast(store.error ?? 'Could not plan today.');
      }
    } finally {
      if (mounted) setState(() => _isPlanningDay = false);
    }
  }

  /// Ticks a task off, and refreshes the Roadmap tab when the task came from it.
  ///
  /// `complete_task` flips `milestone_tasks.done` in the same transaction, so the
  /// database is already in step — but RoadmapStore holds its own copy and the
  /// shell keeps both tabs alive, so without this the roadmap shows a stale
  /// checkbox until a pull-to-refresh. Same reason [_createGoal] reloads
  /// ProfileStore.
  Future<void> _toggle(DailyTask task) async {
    final isCompleting = !task.done;
    if (isCompleting) {
      HapticFeedback.lightImpact();
    } else {
      _hasShownStreakModal = false;
    }

    await context.read<HomeStore>().toggleTask(task);
    
    if (mounted && isCompleting) {
      final store = context.read<HomeStore>();
      if (!_hasShownStreakModal &&
          store.doneCount == store.tasks.length &&
          store.tasks.isNotEmpty) {
        _hasShownStreakModal = true;
        // The sheet's week dots come from here. The Profile tab used to load it
        // at launch; tabs now load when first opened, and this also picks up
        // the day just completed.
        context.read<GamificationStore>().load();
        _confetti.play();
        HapticFeedback.heavyImpact();
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) showStreakCelebrationSheet(context);
        });
      }
    }

    if (!mounted || task.milestoneTaskId == null) return;
    await context.read<RoadmapStore>().load();
  }

  /// Tap: a pending task is ticked, with Undo for a few seconds. A done task
  /// stays done — reopening it is a long-press, so a stray tap can't undo it.
  Future<void> _tapTask(DailyTask task) async {
    if (task.done) {
      showTaskAlreadyDoneHint(context);
      return;
    }
    final store = context.read<HomeStore>();
    // The tick is on screen as soon as the toggle starts (it's optimistic), so
    // Undo appears with it rather than after the save and the roadmap reload.
    final saving = _toggle(task);
    final bar = showTaskDoneSnack(context, title: task.title, onUndo: () async {
      // Undo tapped while the tick is still saving: one write at a time, so
      // wait for it rather than have the store turn the undo away.
      await saving;
      final now = store.tasks.where((t) => t.id == task.id).firstOrNull;
      if (now != null && now.done && mounted) await _toggle(now);
    });
    await saving;
    if (!mounted) return;
    // The save failed and the tick went back: nothing to undo.
    final saved = store.tasks.where((t) => t.id == task.id).firstOrNull;
    if (saved == null || !saved.done) bar.close();
  }

  /// Long-press: a done task goes back on the list, after asking.
  Future<void> _reopenTask(DailyTask task) async {
    if (!task.done) return;
    if (!await confirmReopenTask(context, task.title) || !mounted) return;
    final now = context
        .read<HomeStore>()
        .tasks
        .where((t) => t.id == task.id)
        .firstOrNull;
    if (now != null && now.done) await _toggle(now);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final store = context.watch<HomeStore>();
    final profile = store.profile;
    final goal = store.goal;
    // The selected goal's exams are all sat: no countdown or catch-up for
    // it — just the result and a way on to the next goal.
    final finished = store.examsOver;
    // Every goal is finished: nothing left to plan or practise for.
    final allDone = goal != null && store.openGoals.isEmpty;

    final firstName = (profile?.fullName ?? '').trim().split(' ').first;

    return Stack(
      children: [
        RefreshIndicator(
      color: p.primary,
      onRefresh: () {
        context.read<WeakSpotsStore>().load();
        return context.read<HomeStore>().load();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
        children: [
          // greeting header
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_greeting,
                        style: TextStyle(color: p.ink2, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(firstName.isEmpty ? 'Hey 👋' : '$firstName 👋',
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6)),
                  ],
                ),
              ),
                const NotificationBell(),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () {
                  if (widget.onOpenProfile != null) {
                    widget.onOpenProfile!();
                  } else {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const ProfileScreen()),
                    );
                  }
                },
                child: Tooltip(
                  message: 'View Profile',
                  child: GradAvatar(profile?.initial ?? '?', size: 46),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          if (store.error != null)
            ErrorNotice(
              message: store.error!,
              onRetry: () => context.read<HomeStore>().load(),
            ),

          // Every goal, one tap to switch, and one to add another.
          if (goal != null) ...[
            _GoalBar(
              goals: store.allGoals,
              selectedId: goal.id,
              isOver: store.goalOver,
              onSwitch: store.busy ? null : _switchTo,
              onAdd: store.busy ? null : _createGoal,
            ),
            const SizedBox(height: 14),
          ],

          // hero streak / progress card
          if (store.loading && !store.loaded)
            const LoadingBlock(height: 230)
          else if (goal == null)
            EmptyState(
              icon: Symbols.flag,
              title: 'No study goal yet',
              message: 'Name your exam and StudyTrail will plan around it. '
                  'You can keep a goal for each exam you\'re preparing for.',
              actionLabel: 'Create a study goal',
              onAction: _createGoal,
            )
          else
            _HeroCard(
              goal: goal,
              store: store,
              finished: finished,
              nextGoal: store.nextOpenGoal,
              result: store.resultOf(goal),
              focusMinutes: store.goalFocusMinutes,
              onResult: store.busy ? null : () => _editResult(goal),
              onNewGoal: store.busy ? null : _createGoal,
              onSwitch: store.busy ? null : _switchTo,
            ),
          if (store.nextExam case final next?) ...[
            const SizedBox(height: 10),
            _NextExamStrip(subject: next),
          ],
          if (store.finalStretch case final stretch?) ...[
            const SizedBox(height: 12),
            _FinalStretchCard(
              stretch: stretch,
              dueCards: store.dueCards,
              askedMost: store.askedMost,
              hasWeakSpots:
                  context.watch<WeakSpotsStore>().topics.isNotEmpty,
              onWeakQuiz: () => _practiceWeak(quiz: true),
              onQuiz: widget.onOpenQuiz,
              onCards: _openDueCards,
              onSheet: () => showRevisionSheetPicker(context,
                  goalId: stretch.goal.id, subjectId: stretch.subject?.id),
              onUnit: _sheetForUnit,
            ),
          ],
          const SizedBox(height: 22),

          // No catch-up — that's more new topics — once the selected goal's
          // paper is two days off.
          if (store.pace case final pace?
              when pace.needsCatchUp &&
                  !finished &&
                  !(goal != null && store.inFinalStretch(goal))) ...[
            _CatchUpBanner(
              pace: pace,
              busy: store.busy,
              onCatchUp: _catchUp,
            ),
            const SizedBox(height: 18),
          ],

          // today's plan: every open goal's tasks, whichever is selected.
          // Gone once all of them are finished, unless something was still
          // left on today's list.
          if (!allDone || store.tasks.isNotEmpty) ...[
          CardHeader(
            'Today’s plan',
            action: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${store.tasks.length} task'
                  '${store.tasks.length == 1 ? '' : 's'}',
                  style: TextStyle(
                      color: p.ink3, fontSize: 13, fontWeight: FontWeight.w700),
                ),
                if (goal != null && !allDone) ...[
                  const SizedBox(width: 10),
                  SoftChip(
                    _isPlanningDay ? 'Planning...' : 'Plan day',
                    icon: _isPlanningDay ? null : Symbols.playlist_add,
                    customLeading: _isPlanningDay
                        ? SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: p.primary,
                            ),
                          )
                        : null,
                    tone: ChipTone.primary,
                    onTap: store.busy || _isPlanningDay ? null : _planDay,
                  ),
                ],
              ],
            ),
          ),
          if (_isPlanningDay || (store.loading && !store.loaded))
            const LoadingBlock(height: 74)
          else if (store.tasks.isEmpty)
            EmptyState(
              icon: Symbols.checklist,
              title: 'Nothing scheduled',
              message: goal == null
                  ? 'Create a goal to get a daily plan.'
                  : store.openGoals.length > 1
                      ? "Pull the next few topics off each goal's roadmap "
                          'and start there.'
                      : 'Pull the next few topics off your roadmap and start there.',
              actionLabel:
                  goal == null || store.busy || _isPlanningDay ? null : 'Plan today from roadmap',
              onAction: goal == null || store.busy || _isPlanningDay ? null : _planDay,
            )
          else
            for (final task in store.tasks)
              AppearIn(
                key: ValueKey(task.id),
                child: _TaskTile(
                  task: task,
                  goalName: store.goalNameOf(task),
                  onTap: () => _tapTask(task),
                  onLongPress: () => _reopenTask(task),
                ),
              ),
          const SizedBox(height: 20),
          ],

          if (!allDone)
            _WeakSpotsCard(
              store: context.watch<WeakSpotsStore>(),
              onQuiz: () => _practiceWeak(quiz: true),
              onCards: () => _practiceWeak(quiz: false),
            ),

          // subject progress
          if (store.subjects.isNotEmpty) ...[
            CardHeader('Subjects'),
            AppCard(
              child: Column(
                children: [
                  for (var i = 0; i < store.subjects.length; i++) ...[
                    if (i > 0) const SizedBox(height: 16),
                    _SubjectRow(
                      store.subjects[i],
                      onSetExam: store.busy
                          ? null
                          : () => _pickExamDate(store.subjects[i]),
                      syllabus: store.syllabusOf(store.subjects[i]),
                      readingSyllabus:
                          store.readingSyllabusFor == store.subjects[i].id,
                      onSyllabus: store.busy
                          ? null
                          : () =>
                              showSyllabusSheet(context, store.subjects[i]),
                    ),
                  ],
                ],
              ),
            ),
          ],
          ],
        ),
      ),
      Align(
        alignment: Alignment.topCenter,
        child: ConfettiWidget(
          confettiController: _confetti,
          blastDirectionality: BlastDirectionality.explosive,
          emissionFrequency: 0.05,
          numberOfParticles: 25,
          maxBlastForce: 20,
          minBlastForce: 8,
          gravity: 0.2,
        ),
      ),
    ],
  );
  }
}

/// One chip per goal (tap to make it the selected one) and "New goal".
///
/// Open goals come first. A finished goal keeps its chip, with a tick, so
/// its record is a tap away; the selected goal's chip is filled.
class _GoalBar extends StatelessWidget {
  const _GoalBar({
    required this.goals,
    required this.selectedId,
    required this.isOver,
    this.onSwitch,
    this.onAdd,
  });

  final List<Goal> goals;
  final String selectedId;
  final bool Function(Goal) isOver;
  final ValueChanged<String>? onSwitch;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final ordered = [
      ...goals.where((g) => !isOver(g)),
      ...goals.where(isOver),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (final g in ordered) ...[
            _GoalChip(
              label: g.name,
              selected: g.id == selectedId,
              done: isOver(g),
              daysLeft: g.daysLeft,
              onTap: g.id == selectedId || onSwitch == null
                  ? null
                  : () => onSwitch!(g.id),
            ),
            const SizedBox(width: 8),
          ],
          _GoalChip(label: 'New goal', add: true, onTap: onAdd),
        ],
      ),
    );
  }
}

class _GoalChip extends StatelessWidget {
  const _GoalChip({
    required this.label,
    this.selected = false,
    this.done = false,
    this.add = false,
    this.daysLeft,
    this.onTap,
  });

  final String label;
  final bool selected, done, add;

  /// Shown as "12d" beside an open goal's name, so two goals' deadlines can
  /// be compared at a glance.
  final int? daysLeft;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final (Color bg, Color fg) = selected
        ? (p.primary, p.onPrimary)
        : done
            ? (p.greenSoft, p.green)
            : add
                ? (Colors.transparent, p.coral)
                : (p.card2, p.ink2);
    final days = switch (daysLeft) {
      _ when done || add => null,
      0 => 'today',
      final d? => '${d}d',
      null => null,
    };
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: add
                ? Border.all(color: p.coral.withValues(alpha: 0.5), width: 1.4)
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                  add
                      ? Symbols.add
                      : done
                          ? Symbols.check_circle
                          : Symbols.flag,
                  size: 16,
                  color: fg,
                  fill: done ? 1 : 0),
              const SizedBox(width: 6),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: fg, fontSize: 13, fontWeight: FontWeight.w700)),
              ),
              if (days != null) ...[
                const SizedBox(width: 6),
                Text(days,
                    style: TextStyle(
                        color: fg.withValues(alpha: 0.75),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown when the roadmap has slipped: missed days, or fewer topics done than
/// a straight line to the exam says there should be.
class _CatchUpBanner extends StatelessWidget {
  const _CatchUpBanner({
    required this.pace,
    required this.busy,
    required this.onCatchUp,
  });

  final RoadmapPace pace;
  final bool busy;
  final VoidCallback onCatchUp;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final String headline;
    if (pace.overdue > 0) {
      headline = '${pace.overdue} task${pace.overdue == 1 ? '' : 's'} '
          'missed on earlier days';
    } else {
      headline = '${pace.behind} topic${pace.behind == 1 ? '' : 's'} '
          'behind your plan';
    }
    return AppCard(
      color: p.amberSoft.withValues(alpha: 0.5),
      shadow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Symbols.running_with_errors, color: p.onAmber, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(headline,
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(
                        '${pace.perDay} a day finishes your roadmap in the '
                        '${pace.daysLeft} day${pace.daysLeft == 1 ? '' : 's'} left.',
                        style: TextStyle(color: p.ink2, fontSize: 12.5)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Its own row: beside the text it squeezed the message to a sliver
          // on narrow phones.
          Align(
            alignment: Alignment.centerRight,
            child: PillButton('Catch up',
                icon: Symbols.event_repeat,
                expand: false,
                onTap: busy ? null : onCatchUp),
          ),
        ],
      ),
    );
  }
}

/// The units the student keeps missing, with practice aimed at them.
///
/// Before there's any evidence it's a one-line hint rather than an empty card,
/// so Home isn't padded with a section that has nothing to say yet.
class _WeakSpotsCard extends StatelessWidget {
  const _WeakSpotsCard({
    required this.store,
    required this.onQuiz,
    required this.onCards,
  });

  final WeakSpotsStore store;
  final VoidCallback onQuiz;
  final VoidCallback onCards;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final topics = store.topics;

    if (topics.isEmpty) {
      if (!store.loaded) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Row(
          children: [
            Icon(Symbols.target, size: 18, color: p.ink3),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Take a quiz or review cards and your weak spots will show '
                'up here.',
                style: TextStyle(color: p.ink3, fontSize: 12.5, height: 1.35),
              ),
            ),
          ],
        ),
      );
    }

    final busy = store.busy;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardHeader('Weak spots'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < topics.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(topics[i].name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: p.ink,
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(topics[i].evidence,
                                style: TextStyle(
                                    color: p.ink3, fontSize: 12)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      SoftChip(
                        '${(topics[i].missRate * 100).round()}% missed',
                        tone: ChipTone.coral,
                        small: true,
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: PillButton(
                        store.making == 'quiz' ? 'Writing…' : 'Practice quiz',
                        icon: store.making == 'quiz' ? null : Symbols.quiz,
                        onTap: busy ? null : onQuiz,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: PillButton(
                        store.making == 'cards' ? 'Writing…' : 'Review cards',
                        icon: store.making == 'cards' ? null : Symbols.style,
                        variant: PillVariant.outline,
                        onTap: busy ? null : onCards,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.goal,
    required this.store,
    this.finished = false,
    this.nextGoal,
    this.onNewGoal,
    this.onSwitch,
    this.result,
    this.focusMinutes,
    this.onResult,
  });

  /// How the exam went, once said ([finished] only).
  final GoalResult? result;

  /// Minutes focused on the goal's subjects ([finished] only).
  final int? focusMinutes;

  /// Opens the "How did it go?" sheet.
  final VoidCallback? onResult;

  /// "78% · Felt good · Hard: SQL, Joins".
  static String _resultLine(GoalResult r) {
    final line = [
      if (r.score case final s?) '${(s * 100).round()}%',
      if (r.feelingLabel case final f?) 'Felt ${f.toLowerCase()}',
      if (r.hardUnits.isNotEmpty) 'Hard: ${r.hardUnits.take(3).join(', ')}',
    ].join(' · ');
    return line.isEmpty ? 'Your result is saved' : line;
  }

  final Goal goal;
  final HomeStore store;

  /// Every exam of the goal is behind the student ([HomeStore.examsOver]).
  final bool finished;

  /// Another goal still to work on. A [finished] card points to it rather
  /// than to a new goal.
  final Goal? nextGoal;

  /// Opens the new-goal form; offered once the goal is [finished].
  final VoidCallback? onNewGoal;

  /// Selects another goal by id.
  final ValueChanged<String>? onSwitch;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final percent = goal.overallPercent / 100;
    final covered = goal.overallPercent.round();
    final streak = store.streak.currentStreak;
    final daysLeft = goal.daysLeft;
    final exam = goal.examDate;

    final String subtitle;
    if (finished) {
      subtitle = 'Exam over · you covered $covered% of your roadmap';
    } else if (covered >= 100) {
      subtitle = 'Roadmap complete — revise until the exam';
    } else {
      subtitle = 'You’re $covered% through your roadmap';
    }

    return AppCard(
      gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [p.primary, p.primary2]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: InkWell(
                onTap: () => showStreakCelebrationSheet(context),
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(999)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Symbols.local_fire_department,
                        color: Color(0xFFFFC773), size: 18, fill: 1),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                          streak == 0
                              ? 'Start your streak'
                              : '$streak-day streak',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800)),
                    ),
                  ]),
                ),
              ),
              ),
              const SizedBox(width: 10),
              if (finished)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Symbols.verified,
                      color: Colors.white, size: 16, fill: 1),
                  const SizedBox(width: 4),
                  Text('Finished',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800)),
                ])
              else if ((goal.roadmapDays ?? 0) > 0)
                Text('Day ${goal.currentDay} / ${goal.roadmapDays}',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 16),
          Text(goal.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(subtitle,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: percent.clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: Colors.white.withValues(alpha: 0.22),
              valueColor: const AlwaysStoppedAnimation(Color(0xFFFFC773)),
            ),
          ),
          const SizedBox(height: 16),
          if (finished) ...[
            Row(
              children: [
                if (result?.marksLabel case final marks?)
                  _HeroStat(marks, 'Scored'),
                _HeroStat('$covered%', 'Roadmap covered'),
                if (focusMinutes case final m? when m > 0)
                  _HeroStat(focusTimeLabel(m), 'Focused')
                else
                  _HeroStat('${store.streak.bestStreak}', 'Best streak'),
                if (result?.marksLabel == null && exam != null)
                  _HeroStat(
                      '${exam.day} ${_HomeScreenState._monthNames[exam.month - 1]}',
                      'Exam date'),
              ],
            ),
            const SizedBox(height: 12),
            // How it went: asked once, then shown, and editable.
            _HeroLink(
              icon: result == null ? Symbols.rate_review : Symbols.edit,
              text: switch (result) {
                null => 'How did it go? Add your marks and what was hard',
                final r => _resultLine(r),
              },
              onTap: onResult,
            ),
            const SizedBox(height: 14),
            if (nextGoal case final next?)
              PillButton('Continue: ${next.name}',
                  icon: Symbols.arrow_forward,
                  variant: PillVariant.coral,
                  onTap: onSwitch == null ? null : () => onSwitch!(next.id))
            else
              PillButton('Set your next target',
                  icon: Symbols.flag,
                  variant: PillVariant.coral,
                  onTap: onNewGoal),
          ] else
          Row(
            children: [
              _HeroStat('${store.doneCount}', 'Done today'),
              _HeroStat('${store.tasks.length}', 'Tasks today'),
              if (daysLeft != null && daysLeft <= 7)
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                    decoration: BoxDecoration(
                      color: daysLeft <= 3 ? p.error : const Color(0xFFFFC773),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Text(daysLeft == 0 ? 'Today' : '$daysLeft',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                height: 1.1)),
                        Text(
                            switch (daysLeft) {
                              0 => 'Exam day!',
                              1 => 'Day left!',
                              _ => 'Days left!',
                            },
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                )
              else
                _HeroStat(daysLeft == null ? '—' : '$daysLeft', 'Days left'),
            ],
          ),
        ],
      ),
    );
  }
}

/// A tappable line on the hero card's gradient.
class _HeroLink extends StatelessWidget {
  const _HeroLink({required this.icon, required this.text, this.onTap});

  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ),
              if (onTap != null)
                const Icon(Symbols.chevron_right,
                    color: Colors.white, size: 18),
            ],
          ),
        ),
      );
}

/// A paper in the next two days: what to do instead of new topics.
class _FinalStretchCard extends StatelessWidget {
  const _FinalStretchCard({
    required this.stretch,
    required this.dueCards,
    required this.askedMost,
    required this.hasWeakSpots,
    required this.onWeakQuiz,
    required this.onCards,
    required this.onSheet,
    required this.onUnit,
    this.onQuiz,
  });

  final FinalStretch stretch;
  final int dueCards;
  final List<ExamTopic> askedMost;
  final bool hasWeakSpots;
  final VoidCallback onWeakQuiz;

  /// The Quiz tab, when there are no weak spots to quiz on yet.
  final VoidCallback? onQuiz;
  final VoidCallback onCards;
  final VoidCallback onSheet;
  final ValueChanged<String> onUnit;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final today = stretch.days == 0;
    return AppCard(
      color: p.coralSoft.withValues(alpha: 0.55),
      shadow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Symbols.flag_circle, color: p.coral, size: 26, fill: 1),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Final stretch: ${stretch.paper} ${stretch.when}',
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 15,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(
                        today
                            ? 'A light recap, then go. Good luck!'
                            : 'No new topics now. Revise what you know.',
                        style: TextStyle(color: p.ink2, fontSize: 12.5)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (hasWeakSpots)
            _StretchAction(
                icon: Symbols.target,
                title: 'Quiz your weak spots',
                subtitle: 'A short quiz on what you keep missing',
                onTap: onWeakQuiz)
          else if (onQuiz != null)
            _StretchAction(
                icon: Symbols.quiz,
                title: 'Take a practice quiz',
                subtitle: 'Check what has stuck',
                onTap: onQuiz!),
          if (dueCards > 0)
            _StretchAction(
                icon: Symbols.style,
                title: 'Review $dueCards due card${dueCards == 1 ? '' : 's'}',
                subtitle: 'Spaced repetition, while it still helps',
                onTap: onCards),
          for (final t in askedMost.take(2))
            _StretchAction(
                icon: Symbols.history_edu,
                title: 'Most asked: ${t.unitLabel}',
                subtitle: 'Asked ${t.timesAsked} time'
                    '${t.timesAsked == 1 ? '' : 's'} in past papers · '
                    'revision sheet',
                onTap: () => onUnit(t.unitLabel)),
          _StretchAction(
              icon: Symbols.article,
              title: 'Read a revision sheet',
              subtitle: 'One page per unit, from your notes',
              onTap: onSheet),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Symbols.bedtime, color: p.ink3, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                    today
                        ? 'Eat, breathe, read each question twice.'
                        : 'Last focus block by 10 pm, then sleep. Rest is '
                            'revision too.',
                    style: TextStyle(color: p.ink3, fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StretchAction extends StatelessWidget {
  const _StretchAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            IconTile(icon, bg: p.card, fg: p.coral, size: 34, radius: 10),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700)),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.ink3, fontSize: 11.5)),
                ],
              ),
            ),
            Icon(Symbols.chevron_right, color: p.ink3, size: 18),
          ],
        ),
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat(this.value, this.label);
  final String value, label;
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800)),
          Text(label,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8), fontSize: 11.5)),
        ],
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({
    required this.task,
    required this.onTap,
    required this.onLongPress,
    this.goalName,
  });

  final DailyTask task;

  /// The goal the task belongs to, when there's more than one on the go.
  final String? goalName;
  final VoidCallback onTap;

  /// Reopens a done task (after a confirmation).
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final style = SubjectStyle.of(context, name: task.subjectName ?? '');
    final done = task.done;

    // Tag colour follows the task's state, matching the original design.
    final (tagBg, tagFg) = switch (task.tag) {
      TaskTag.done => (p.greenSoft, p.green),
      TaskTag.quiz => (p.amberSoft, p.onAmber),
      TaskTag.now => (p.coralSoft, p.coralInk),
    };

    final meta = [
      ?goalName,
      if ((task.subjectName ?? '').isNotEmpty) task.subjectName!,
      if (task.durationLabel.isNotEmpty) task.durationLabel,
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      onLongPress: done ? onLongPress : null,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(20),
          boxShadow: p.shadowSm,
        ),
        child: Row(
          children: [
            // The tick pops in, so finishing a task feels like something.
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              transitionBuilder: (child, a) => ScaleTransition(
                  scale: CurvedAnimation(parent: a, curve: Curves.easeOutBack),
                  child: child),
              child: IconTile(
                done ? Symbols.check : style.icon,
                key: ValueKey(done),
                bg: done ? p.greenSoft : style.color.withValues(alpha: 0.14),
                fg: done ? p.green : style.color,
                size: 46,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(task.title,
                      style: TextStyle(
                          color: done ? p.ink3 : p.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          decoration:
                              done ? TextDecoration.lineThrough : null)),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(meta,
                        style: TextStyle(color: p.ink3, fontSize: 12.5)),
                  ],
                ],
              ),
            ),
            Tag(task.tag.label, bg: tagBg, fg: tagFg),
          ],
        ),
      ),
    );
  }
}

/// "Next exam: DBMS · 15 Oct · in 13 days" under the hero card.
class _NextExamStrip extends StatelessWidget {
  const _NextExamStrip({required this.subject});

  final Subject subject;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final days = subject.daysUntilExam() ?? 0;
    final exam = subject.examDate!;
    final when = switch (days) {
      0 => 'today — good luck!',
      1 => 'tomorrow',
      _ => 'in $days days',
    };
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: days <= 3 ? p.coralSoft : p.card,
      shadow: false,
      child: Row(
        children: [
          Icon(Symbols.event, size: 20, color: days <= 3 ? p.coral : p.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: 'Next exam: ',
                    style: TextStyle(color: p.ink3, fontSize: 13)),
                TextSpan(
                    text: subject.name,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800)),
                TextSpan(
                    text: ' · ${exam.day} '
                        '${_HomeScreenState._monthNames[exam.month - 1]} · $when',
                    style: TextStyle(color: p.ink2, fontSize: 13)),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small tappable line under a subject: its exam date, its syllabus.
class _RowLink extends StatelessWidget {
  const _RowLink({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  /// Shows a spinner instead of the icon.
  final bool busy;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.6, color: color),
              )
            else
              Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

class _SubjectRow extends StatelessWidget {
  const _SubjectRow(
    this.subject, {
    this.onSetExam,
    this.syllabus,
    this.readingSyllabus = false,
    this.onSyllabus,
  });

  final Subject subject;

  /// Opens the date picker for this subject's exam.
  final VoidCallback? onSetExam;

  /// This subject's syllabus, if it has one.
  final StudyMaterial? syllabus;

  /// Its syllabus is being uploaded and read right now.
  final bool readingSyllabus;

  /// Opens the syllabus sheet: add, replace or remove.
  final VoidCallback? onSyllabus;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final style = SubjectStyle.of(
      context,
      name: subject.name,
      iconKey: subject.iconKey,
      colorKey: subject.colorKey,
    );
    final value = (subject.progress / 100).clamp(0.0, 1.0);

    return Row(
      children: [
        IconTile(style.icon,
            bg: style.color.withValues(alpha: 0.14),
            fg: style.color,
            size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(subject.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 8),
                  Text('${subject.progress.round()}%',
                      style: TextStyle(
                          color: p.ink2,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 7),
              ProgressTrack(value, color: style.color, height: 7),
              const SizedBox(height: 6),
              Wrap(
                spacing: 14,
                runSpacing: 4,
                children: [
                  _RowLink(
                    icon: Symbols.event,
                    label: switch (subject.daysUntilExam()) {
                      null => 'Set exam date',
                      < 0 => 'Exam done',
                      0 => 'Exam today',
                      final d => 'Exam in $d day${d == 1 ? '' : 's'}',
                    },
                    color: subject.examDate == null ? p.primary : p.ink3,
                    onTap: onSetExam,
                  ),
                  if (readingSyllabus)
                    _RowLink(
                      icon: Symbols.hourglass_top,
                      label: 'Reading syllabus…',
                      color: p.ink3,
                      busy: true,
                    )
                  else if (syllabus == null)
                    _RowLink(
                      icon: Symbols.upload_file,
                      label: 'Add syllabus',
                      color: p.primary,
                      onTap: onSyllabus,
                    )
                  else if (syllabus!.isReady)
                    _RowLink(
                      icon: Symbols.description,
                      label: 'Syllabus added',
                      color: p.green,
                      onTap: onSyllabus,
                    )
                  else
                    _RowLink(
                      icon: Symbols.error,
                      label: "Syllabus couldn't be read",
                      color: p.error,
                      onTap: onSyllabus,
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
