// Tests for the four core student-journey writes, with Supabase faked out.
//
// The repositories reach Supabase through a global `db` getter, so there is no
// client to inject — the seam is the repository itself. Every fake here
// subclasses the real one and overrides only the methods under test, which means
// the store's own logic (optimistic writes, reverts, derived state) runs for
// real while nothing touches the network.
//
// Widget-level tests live in `widget_test.dart`.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:studytrail_flutter/data/repositories.dart';
import 'package:studytrail_flutter/models/models.dart';
import 'package:studytrail_flutter/state/stores.dart';

void main() {
  group('AuthStore signup bootstrap', () {
    // `profiles` and `streaks` are created by the `handle_new_user` trigger, so
    // the client has nothing to insert — the only thing signup has to get right
    // is which of the two endings it got.
    test('no session back means the project wants the email confirmed',
        () async {
      final auth = _FakeAuth();
      final store = AuthStore(repo: auth);
      addTearDown(store.dispose);

      expect(await store.signUp(
            fullName: 'Asha Patel',
            email: 'asha@example.com',
            password: 'a-long-enough-password',
          ),
          isTrue);

      expect(store.awaitingEmailConfirmation, isTrue);
      expect(store.status, AuthStatus.signedOut);
      expect(store.error, isNull);
      // The trigger reads full_name out of the signup metadata, so it has to be
      // passed through rather than saved afterwards.
      expect(auth.signedUpName, 'Asha Patel');
    });

    test('a session back signs the student straight in', () async {
      final store = AuthStore(repo: _FakeAuth(sessionOnSignUp: _session));
      addTearDown(store.dispose);

      await store.signUp(
        fullName: 'Asha Patel',
        email: 'asha@example.com',
        password: 'a-long-enough-password',
      );
      // The gate follows the auth stream, not the return value, and stream
      // events land a microtask later.
      await Future<void>.delayed(Duration.zero);

      expect(store.awaitingEmailConfirmation, isFalse);
      expect(store.status, AuthStatus.signedIn);
    });

    test('a rejected signup reports the reason and stays signed out', () async {
      final store = AuthStore(
          repo: _FakeAuth(failure: AuthException('User already registered')));
      addTearDown(store.dispose);

      expect(await store.signUp(
            fullName: 'Asha Patel',
            email: 'taken@example.com',
            password: 'a-long-enough-password',
          ),
          isFalse);

      expect(store.status, AuthStatus.signedOut);
      expect(store.error, 'That email already has an account. Try signing in.');
      expect(store.busy, isFalse);
    });
  });

  group('OnboardingStore.createGoal', () {
    // One RPC, not the old insert-goal-then-insert-subjects pair: a half-created
    // goal used to leave onboarding unable to finish (`DECISIONS.md` D-005).
    test('creates the goal and its subjects in one call', () async {
      final goals = _FakeGoals();
      final store = OnboardingStore(goals: goals);

      expect(await store.createGoal(
            name: 'Physics final',
            examDate: DateTime(2026, 11, 15),
            pace: Pace.intense,
            subjects: const ['Kinematics', 'Optics'],
            subjectExamDates: [DateTime(2026, 11, 10), DateTime(2026, 11, 15)],
          ),
          isTrue);

      expect(store.createdGoal?.name, 'Physics final');
      expect(store.error, isNull);
      expect(goals.lastSubjects, ['Kinematics', 'Optics']);
      expect(goals.lastSubjectDates,
          [DateTime(2026, 11, 10), DateTime(2026, 11, 15)]);
      expect(goals.lastPace, Pace.intense);
    });

    test('a failed create leaves no goal behind and says why', () async {
      final store = OnboardingStore(goals: _FakeGoals(failing: true));

      expect(await store.createGoal(name: 'Physics final'), isFalse);
      expect(store.createdGoal, isNull);
      expect(store.error, isNotNull);
      // Still usable: the screen's retry button calls the same method again.
      expect(store.busy, isFalse);
    });
  });

  group('HomeStore.toggleTask retry', () {
    // REVIEW.md P1: the tick used to be applied locally and then forgotten if
    // the write failed, so the checklist claimed work the database never saw.
    test('a failed tick goes back to unticked, and a retry sticks', () async {
      final tasks = _FakeTasks(today: [_task], failing: true);
      final store = _homeStore(tasks: tasks);
      await store.load();
      expect(store.tasks.single.done, isFalse);

      await store.toggleTask(store.tasks.single);
      expect(store.tasks.single.done, isFalse, reason: 'reverted');
      expect(store.tasks.single.tag, TaskTag.now);
      expect(store.error, isNotNull);
      expect(store.doneCount, 0);

      tasks.failing = false;
      await store.toggleTask(store.tasks.single);
      expect(store.tasks.single.done, isTrue);
      expect(store.doneCount, 1);
      // `complete_task` rolls the streak forward, so the header chip is re-read
      // rather than guessed at.
      expect(store.streak.currentStreak, 3);
    });

    test('ticking a task that was never scheduled from the roadmap leaves '
        'the roadmap alone', () async {
      final roadmap = _FakeRoadmap();
      final store = _homeStore(
          tasks: _FakeTasks(today: [_task]), roadmap: roadmap);
      await store.load();

      await store.toggleTask(store.tasks.single);
      expect(store.tasks.single.done, isTrue);
      expect(roadmap.resyncs, isEmpty);
      expect(roadmap.recomputes, isEmpty);
    });
  });

  group('FlashcardStore.grade retry', () {
    // Also REVIEW.md P1: the advance is optimistic so review doesn't stutter,
    // but a card whose grade never landed is still due in the database — losing
    // it made the session claim a review that never happened.
    test('a failed grade puts the card back on the queue', () async {
      final cards = _FakeFlashcards(due: [_card, _otherCard], failing: true);
      final store = FlashcardStore(cards: cards);

      await store.startSession();
      expect(store.current?.id, 'card-1');
      store.reveal();
      expect(store.revealed, isTrue);

      await store.grade(SrGrade.good);
      // Advanced past it either way — but re-queued at the end, and not counted.
      expect(store.reviewedThisSession, 0);
      expect(store.queue.map((c) => c.id), ['card-1', 'card-2', 'card-1']);
      expect(store.current?.id, 'card-2');
      expect(store.revealed, isFalse);

      cards.failing = false;
      await store.grade(SrGrade.easy);
      expect(store.reviewedThisSession, 1);
      expect(cards.graded, [('card-2', SrGrade.easy)]);
      // The re-queued card comes round again instead of vanishing.
      expect(store.current?.id, 'card-1');
      expect(store.sessionFinished, isFalse);
    });

    test('finishing the queue refreshes the deck counts', () async {
      final cards = _FakeFlashcards(due: [_card]);
      final store = FlashcardStore(cards: cards);

      await store.startSession();
      await store.grade(SrGrade.good);

      expect(store.sessionFinished, isTrue);
      expect(cards.deckReads, 1, reason: 'due count moves after the session');
      expect(store.decks.single.due, 0);
    });
  });

  group('HomeStore.planDayFromRoadmap', () {
    // The gap this closes: `generate-roadmap` writes `milestone_tasks`, which
    // live on their own tab, so Home showed "nothing scheduled" next to a full
    // seven-week plan.
    test('seeds one milestone at a time and never repeats a task', () async {
      final tasks = _FakeTasks();
      final store = _homeStore(
          tasks: tasks, roadmap: _FakeRoadmap(plan: _plan));
      await store.load();
      expect(store.goal, isNotNull);

      expect(await store.planDayFromRoadmap(limit: 2), PlanDayResult.added);
      expect(store.plannedCount, 2);
      expect(store.plannedFrom, 'Week 1');
      // Week 1's first task is already done, so it is skipped rather than
      // handed back to the student.
      expect(tasks.inserted.map((t) => t.milestoneTaskId), ['w1-b', 'w1-c']);
      // The link that lets `complete_task` tick the roadmap in the same
      // transaction. Without it this whole feature is just extra typing.
      expect(store.tasks.every((t) => t.milestoneTaskId != null), isTrue);

      // Tapping again moves on instead of scheduling week 1 twice.
      expect(await store.planDayFromRoadmap(limit: 2), PlanDayResult.added);
      expect(store.plannedFrom, 'Week 2');
      expect(tasks.inserted.length, 4);

      expect(
          await store.planDayFromRoadmap(limit: 2), PlanDayResult.nothingLeft);
      expect(tasks.inserted.length, 4);
    });

    test('says so when the goal has no roadmap yet', () async {
      final store = _homeStore(tasks: _FakeTasks());

      await store.load();

      expect(await store.planDayFromRoadmap(), PlanDayResult.noRoadmap);
      expect(store.error, isNull);
    });

    // A seeded task is the only kind whose tick has to reach three more places:
    // `complete_task` owns neither `milestones.state` nor the goal percentage.
    test('ticking a seeded task re-derives what the RPC does not own', () async {
      final tasks = _FakeTasks();
      final roadmap = _FakeRoadmap(plan: _plan);
      final store = _homeStore(tasks: tasks, roadmap: roadmap);
      await store.load();
      await store.planDayFromRoadmap(limit: 1);

      await store.toggleTask(store.tasks.single);

      expect(store.tasks.single.done, isTrue);
      expect(roadmap.resyncs, ['w1-b']);
      expect(roadmap.recomputes, ['goal-1']);
    });
  });
}

HomeStore _homeStore({
  required TaskRepository tasks,
  RoadmapRepository? roadmap,
}) =>
    HomeStore(
      profiles: const _FakeProfiles(),
      goals: _FakeGoals(),
      tasks: tasks,
      game: const _FakeGame(),
      roadmap: roadmap ?? _FakeRoadmap(),
    );

/// Two weeks of a generated roadmap, with week 1's first task already ticked.
const _plan = [
  Milestone(
    id: 'm1',
    title: 'Kinematics',
    weekLabel: 'Week 1',
    tasks: [
      MilestoneTask(id: 'w1-a', name: 'Displacement', done: true),
      MilestoneTask(id: 'w1-b', name: 'Velocity', orderIndex: 1),
      MilestoneTask(id: 'w1-c', name: 'Acceleration', orderIndex: 2),
    ],
  ),
  Milestone(
    id: 'm2',
    title: 'Newton’s laws',
    weekLabel: 'Week 2',
    orderIndex: 1,
    tasks: [
      MilestoneTask(id: 'w2-a', name: 'Free-body diagrams'),
      MilestoneTask(id: 'w2-b', name: 'Friction', orderIndex: 1),
    ],
  ),
];

final _task = DailyTask(
  id: 'task-1',
  title: 'Revise projectile motion',
  scheduledDate: DateTime(2026, 9, 4),
);

final _card = Flashcard(
  id: 'card-1',
  deckId: 'deck-1',
  front: 'Escape velocity',
  back: '11.2 km/s',
  dueAt: DateTime(2026, 9, 1),
);

final _otherCard = Flashcard(
  id: 'card-2',
  deckId: 'deck-1',
  front: 'Terminal velocity',
  back: 'When drag equals weight',
  dueAt: DateTime(2026, 9, 2),
);

/// A session shaped like the one a confirm-email-off project returns. The token
/// is a literal, not a credential.
final _session = Session(
  accessToken: 'fake-access-token',
  tokenType: 'bearer',
  user: const User(
    id: 'user-1',
    appMetadata: {},
    userMetadata: {'full_name': 'Asha Patel'},
    aud: 'authenticated',
    createdAt: '2026-09-04T00:00:00.000Z',
  ),
);

class _FakeAuth extends AuthRepository {
  _FakeAuth({this.sessionOnSignUp, this.failure});

  /// Non-null when the project has email confirmation off. Deliberately not
  /// named `session` — [AuthRepository] already has a getter by that name, and
  /// this is only what signup hands back, not a live session.
  final Session? sessionOnSignUp;
  final Object? failure;

  final _events = StreamController<AuthState>.broadcast();
  String? signedUpName;

  @override
  Stream<AuthState> get authStateChanges => _events.stream;

  @override
  bool get isSignedIn => false;

  @override
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async {
    if (failure != null) throw failure!;
    signedUpName = fullName;
    if (sessionOnSignUp != null) {
      _events.add(AuthState(AuthChangeEvent.signedIn, sessionOnSignUp));
    }
    return AuthResponse(session: sessionOnSignUp);
  }
}

class _FakeGoals extends GoalRepository {
  _FakeGoals({this.failing = false});

  final bool failing;
  List<String>? lastSubjects;
  List<DateTime?>? lastSubjectDates;
  Pace? lastPace;

  @override
  Future<List<Goal>> getGoals() async =>
      const [Goal(id: 'goal-1', name: 'Physics final')];

  @override
  Future<List<Subject>> getSubjects(String goalId) async => const [];

  @override
  Future<Goal> createGoal({
    required String name,
    DateTime? examDate,
    Pace pace = Pace.steady,
    List<String> subjectNames = const [],
    List<DateTime?> subjectExamDates = const [],
  }) async {
    if (failing) throw Exception('create_goal timed out');
    lastSubjects = subjectNames;
    lastSubjectDates = subjectExamDates;
    lastPace = pace;
    return Goal(id: 'goal-1', name: name, examDate: examDate);
  }
}

/// `daily_tasks` in memory, so a second `planDayFromRoadmap` call sees what the
/// first one scheduled — which is the duplicate check under test.
class _FakeTasks extends TaskRepository {
  _FakeTasks({this.today = const [], this.failing = false});

  final List<DailyTask> today;

  /// Flipped mid-test to prove the retry lands.
  bool failing;

  final List<DailyTask> inserted = [];

  @override
  Future<List<DailyTask>> getTodayTasks() async => today;

  @override
  Future<DailyTask> setDone(DailyTask task, bool done) async {
    if (failing) throw Exception('complete_task never answered');
    return task.copyWith(done: done, tag: done ? TaskTag.done : TaskTag.now);
  }

  @override
  Future<Set<String>> getScheduledMilestoneTaskIds(String goalId) async =>
      {for (final task in inserted) task.milestoneTaskId!};

  @override
  Future<List<DailyTask>> createTasksFromRoadmap({
    required String goalId,
    required List<MilestoneTask> tasks,
    DateTime? scheduledDate,
  }) async {
    final rows = [
      for (final task in tasks)
        DailyTask(
          id: 'daily-${task.id}',
          title: task.name,
          milestoneTaskId: task.id,
          scheduledDate: scheduledDate ?? DateTime(2026, 9, 4),
        ),
    ];
    inserted.addAll(rows);
    return rows;
  }
}

class _FakeRoadmap extends RoadmapRepository {
  _FakeRoadmap({this.plan = const []});

  final List<Milestone> plan;

  /// Lists rather than counters, so a test can name what was resynced.
  final List<String> resyncs = [];
  final List<String> recomputes = [];

  @override
  Future<List<Milestone>> getMilestones(String goalId) async => plan;

  @override
  Future<void> resyncMilestoneForTask(String milestoneTaskId) async {
    resyncs.add(milestoneTaskId);
  }

  @override
  Future<double> recomputeGoalProgress(String goalId) async {
    recomputes.add(goalId);
    return 25;
  }
}

class _FakeFlashcards extends FlashcardRepository {
  _FakeFlashcards({this.due = const [], this.failing = false});

  final List<Flashcard> due;
  bool failing;

  final List<(String, SrGrade)> graded = [];
  int deckReads = 0;

  @override
  Future<List<Flashcard>> getDueCards({String? deckId, int limit = 40}) async =>
      due;

  @override
  Future<Flashcard> gradeCard(Flashcard card, SrGrade grade) async {
    if (failing) throw Exception('apply_sr_grade never answered');
    graded.add((card.id, grade));
    return card;
  }

  @override
  Future<List<FlashcardDeck>> getDecks() async {
    deckReads++;
    return const [FlashcardDeck(id: 'deck-1', name: 'Physics', total: 2)];
  }
}

class _FakeProfiles extends ProfileRepository {
  const _FakeProfiles();

  @override
  Future<Profile?> getMyProfile() async => null;
}

class _FakeGame extends GamificationRepository {
  const _FakeGame();

  @override
  Future<Streak> getStreak() async => const Streak(currentStreak: 3);
}
