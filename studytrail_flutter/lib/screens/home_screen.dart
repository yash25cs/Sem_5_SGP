import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:confetti/confetti.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/stores.dart';
import '../theme/app_theme.dart';
import '../theme/subject_style.dart';
import '../widgets/common.dart';
import '../widgets/data_states.dart';
import '../widgets/notification_bell.dart';
import '../widgets/streak_modal.dart';
import 'flashcards_screen.dart';
import 'profile_screen.dart';
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
      context.read<HomeStore>().load();
      context.read<WeakSpotsStore>().load();
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

  /// The goal switcher — every goal the student has, plus a way to add one.
  Future<void> _switchGoal() async {
    final store = context.read<HomeStore>();
    final p = context.p;
    final activeId = store.goal?.id;

    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                child: Text('Your study goals',
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                    'Keep one per exam. StudyTrail plans against the one you '
                    'pick here.',
                    style: TextStyle(color: p.ink3, fontSize: 12.5)),
              ),
              for (final g in store.allGoals)
                ListTile(
                  leading: Icon(Symbols.flag,
                      color: g.id == activeId ? p.primary : p.ink3),
                  title: Text(g.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600)),
                  subtitle: Text(_examLabel(g),
                      style: TextStyle(color: p.ink3, fontSize: 12)),
                  trailing: g.id == activeId
                      ? Icon(Symbols.check, color: p.primary)
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(g.id),
                ),
              ListTile(
                leading: Icon(Symbols.add, color: p.coral),
                title: Text('New goal',
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600)),
                onTap: () => Navigator.of(sheetContext).pop(_newGoalSentinel),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );

    if (picked == null || !mounted) return;
    if (picked == _newGoalSentinel) {
      await _createGoal();
      return;
    }
    final ok = await store.switchGoal(picked);
    if (!ok) _toast(store.error ?? 'Could not switch goal');
  }

  static const _newGoalSentinel = '__new__';

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

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _examLabel(Goal goal) {
    final exam = goal.examDate;
    if (exam == null) return 'No exam date';
    final left = goal.daysLeft;
    final date = '${_months[exam.month - 1]} ${exam.day}';
    return left == null || left < 0 ? date : '$date · $left days left';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final store = context.watch<HomeStore>();
    final profile = store.profile;
    final goal = store.goal;

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

          // Goal switcher. Only worth the row once there's a second goal to
          // switch to — with one, the hero card already names it.
          if (store.allGoals.length > 1) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: SoftChip(goal?.name ?? 'Pick a goal',
                  icon: Symbols.flag,
                  tone: ChipTone.primary,
                  onTap: store.busy ? null : _switchGoal),
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
            _HeroCard(goal: goal, store: store),
          if (store.nextExam case final next?) ...[
            const SizedBox(height: 10),
            _NextExamStrip(subject: next),
          ],
          const SizedBox(height: 22),

          if (store.pace case final pace? when pace.needsCatchUp) ...[
            _CatchUpBanner(
              pace: pace,
              busy: store.busy,
              onCatchUp: _catchUp,
            ),
            const SizedBox(height: 18),
          ],

          // today's plan
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
                if (goal != null) ...[
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
                  : 'Pull the next few topics off your roadmap and start there.',
              actionLabel:
                  goal == null || store.busy || _isPlanningDay ? null : 'Plan today from roadmap',
              onAction: goal == null || store.busy || _isPlanningDay ? null : _planDay,
            )
          else
            for (final task in store.tasks)
              _TaskTile(
                task: task,
                onToggle: () => _toggle(task),
              ),
          const SizedBox(height: 20),

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
  const _HeroCard({required this.goal, required this.store});

  final Goal goal;
  final HomeStore store;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final percent = goal.overallPercent / 100;
    final streak = store.streak.currentStreak;
    final daysLeft = goal.daysLeft;

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
              if ((goal.roadmapDays ?? 0) > 0)
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
          Text('You’re ${goal.overallPercent.round()}% through your roadmap',
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
                        Text('$daysLeft',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                height: 1.1)),
                        const Text('Days left!',
                            style: TextStyle(
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
  const _TaskTile({required this.task, required this.onToggle});

  final DailyTask task;
  final VoidCallback onToggle;

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
      if ((task.subjectName ?? '').isNotEmpty) task.subjectName!,
      if (task.durationLabel.isNotEmpty) task.durationLabel,
    ].join(' · ');

    return InkWell(
      onTap: onToggle,
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
            IconTile(
              done ? Symbols.check : style.icon,
              bg: done ? p.card2 : style.color.withValues(alpha: 0.14),
              fg: done ? p.ink3 : style.color,
              size: 46,
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

class _SubjectRow extends StatelessWidget {
  const _SubjectRow(this.subject, {this.onSetExam});

  final Subject subject;

  /// Opens the date picker for this subject's exam.
  final VoidCallback? onSetExam;

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
              GestureDetector(
                onTap: onSetExam,
                child: Row(
                  children: [
                    Icon(Symbols.event, size: 14, color: p.ink3),
                    const SizedBox(width: 4),
                    Text(
                      switch (subject.daysUntilExam()) {
                        null => 'Set exam date',
                        < 0 => 'Exam done',
                        0 => 'Exam today',
                        final d => 'Exam in $d day${d == 1 ? '' : 's'}',
                      },
                      style: TextStyle(
                          color: subject.examDate == null ? p.primary : p.ink3,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
