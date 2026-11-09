// Two goals at once: both get planned, named and reminded about, whichever is
// selected; Home switches and adds goals in one tap; and a finished goal's
// roadmap can't be generated again.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:studytrail_flutter/data/repositories.dart';
import 'package:studytrail_flutter/models/models.dart';
import 'package:studytrail_flutter/screens/home_screen.dart';
import 'package:studytrail_flutter/services/notification_service.dart';
import 'package:studytrail_flutter/state/reminder_sync.dart';
import 'package:studytrail_flutter/state/stores.dart';
import 'package:studytrail_flutter/theme/app_theme.dart';

DateTime _inDays(int n) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + n);
}

final _dbms = Goal(id: 'dbms', name: 'DBMS end-sem', examDate: _inDays(20));
final _gate =
    Goal(id: 'gate', name: 'GATE prep', examDate: _inDays(5), isActive: false);
final _midSem =
    Goal(id: 'mid', name: 'Mid-sem', examDate: _inDays(-10), isActive: false);

void main() {
  group('HomeStore with two open goals', () {
    late _Tasks tasks;

    Future<HomeStore> load(List<Goal> goals) async {
      tasks = _Tasks();
      final store = HomeStore(
        profiles: const _Profiles(),
        goals: _Goals(goals),
        tasks: tasks,
        game: const _Game(),
        roadmap: _Roadmap(),
      );
      addTearDown(store.dispose);
      await store.load();
      return store;
    }

    test('both are open; the finished one is not', () async {
      final store = await load([_dbms, _gate, _midSem]);
      expect(store.openGoals.map((g) => g.id), ['dbms', 'gate']);
      expect(store.goalOver(_midSem), isTrue);
      expect(store.nextOpenGoal?.id, 'gate');
    });

    test('Plan day pulls from both, the selected goal first', () async {
      final store = await load([_dbms, _gate, _midSem]);
      expect(await store.planDayFromRoadmap(), PlanDayResult.added);
      expect(tasks.plannedFor, ['dbms', 'gate']);
      expect(store.plannedFrom, 'DBMS end-sem (Week 1) and GATE prep (Week 1)');
      // Each task says which goal it's for.
      expect(store.tasks.map(store.goalNameOf),
          everyElement(isIn(['DBMS end-sem', 'GATE prep'])));
    });

    test('with one goal, nothing is named', () async {
      final store = await load([_dbms]);
      await store.planDayFromRoadmap();
      expect(store.plannedFrom, 'Week 1');
      expect(store.goalNameOf(store.tasks.first), isNull);
    });
  });

  testWidgets(
      'Home: a chip per goal, one-tap new goal, and a finished '
      'goal points to the open one', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 1000 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final finished = Goal(
        id: 'mid', name: 'Mid-sem', examDate: _inDays(-10), overallPercent: 70);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<HomeStore>(
            create: (_) => HomeStore(
                  profiles: const _Profiles(),
                  goals: _Goals([finished, _gate]),
                  tasks: _Tasks(),
                  game: const _Game(),
                  roadmap: _Roadmap(),
                )),
        ChangeNotifierProvider<WeakSpotsStore>(
            create: (_) => WeakSpotsStore(quizzes: _Quizzes())),
      ],
      child: MaterialApp(
          theme: AppTheme.light(), home: const Scaffold(body: HomeScreen())),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Mid-sem'), findsWidgets);
    expect(find.text('GATE prep'), findsOneWidget);
    expect(find.text('New goal'), findsOneWidget);
    expect(find.text('Continue: GATE prep'), findsOneWidget);
    expect(find.text('Set your next target'), findsNothing);
    // GATE is still on: today's plan stays, and so do weak spots.
    expect(find.text('Plan day'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Weak spots'), 300,
        scrollable: find.byType(Scrollable).first);
  });

  group('RoadmapStore', () {
    Future<(RoadmapStore, _Roadmap)> load(Goal goal,
        {bool allDone = false}) async {
      final roadmap = _Roadmap(allDone: allDone);
      final store = RoadmapStore(roadmap: roadmap, goals: _Goals([goal]));
      addTearDown(store.dispose);
      await store.load();
      return (store, roadmap);
    }

    test("a finished goal's roadmap can't be generated again", () async {
      final (over, overRoadmap) = await load(_midSem.copyActive());
      expect(over.goalFinished, isTrue);
      expect(await over.generate(), isFalse);

      final (done, doneRoadmap) = await load(_dbms, allDone: true);
      expect(done.allTopicsDone, isTrue);
      expect(await done.generate(), isFalse);
      expect(overRoadmap.generated + doneRoadmap.generated, 0);
    });

    test('an open goal still can', () async {
      final (store, roadmap) = await load(_dbms);
      expect(store.goalFinished, isFalse);
      expect(await store.generate(), isTrue);
      expect(roadmap.generated, 1);
    });
  });

  group('reminders', () {
    test('cover every open goal and its papers, soonest first', () {
      final e = GoalExams.from(
        [_dbms, _gate, _midSem, const Goal(id: 'u', name: 'Undated')],
        [
          Subject(
              id: 's1',
              name: 'Transactions',
              goalId: 'dbms',
              examDate: _inDays(3)),
          Subject(
              id: 's2',
              name: 'Normal forms',
              goalId: 'dbms',
              examDate: _inDays(-1)),
          Subject(
              id: 's3',
              name: 'Old paper',
              goalId: 'mid',
              examDate: _inDays(-10)),
        ],
        DateTime.now(),
      );
      expect(e.openGoals, ['DBMS end-sem', 'GATE prep', 'Undated']);
      expect(e.upcoming.map((x) => x.$1), ['Transactions', 'GATE prep']);
    });

    test('the study nudge names two goals', () {
      expect(NotificationService.studyReminderBody(['DBMS', 'GATE']),
          startsWith('DBMS and GATE both need you today'));
      expect(NotificationService.studyReminderBody(['DBMS']),
          'A focused 25 minutes today keeps your plan on track.');
    });
  });
}

extension on Goal {
  /// The same goal as the selected one.
  Goal copyActive() => Goal(id: id, name: name, examDate: examDate);
}

class _Profiles extends ProfileRepository {
  const _Profiles();
  @override
  Future<Profile?> getMyProfile() async => null;
}

class _Goals extends GoalRepository {
  _Goals(this.goals);
  final List<Goal> goals;

  @override
  Future<List<Goal>> getGoals() async => goals;
  @override
  Future<Goal?> getActiveGoal() async =>
      goals.where((g) => g.isActive).firstOrNull;
  @override
  Future<List<Subject>> getSubjects(String goalId) async => const [];
  @override
  Future<List<Subject>> getAllSubjects() async => const [];
}

class _Tasks extends TaskRepository {
  final plannedFor = <String>[];
  @override
  Future<List<DailyTask>> getTodayTasks() async => const [];
  @override
  Future<Set<String>> getScheduledMilestoneTaskIds(String goalId) async => {};
  @override
  Future<List<DailyTask>> createTasksFromRoadmap({
    required String goalId,
    required List<MilestoneTask> tasks,
    DateTime? scheduledDate,
  }) async {
    plannedFor.add(goalId);
    return [
      for (final t in tasks)
        DailyTask(
            id: '$goalId-${t.id}',
            title: t.name,
            milestoneTaskId: t.id,
            scheduledDate: DateTime.now(),
            goalId: goalId),
    ];
  }
}

class _Game extends GamificationRepository {
  const _Game();
  @override
  Future<Streak> getStreak() async => const Streak();
}

class _Roadmap extends RoadmapRepository {
  _Roadmap({this.allDone = false});
  final bool allDone;
  int generated = 0;

  @override
  Future<RoadmapPace> getPace(String goalId) async =>
      const RoadmapPace(hasRoadmap: true);

  @override
  Future<List<Milestone>> getMilestones(String goalId) async => [
        Milestone(
            id: '$goalId-w1',
            title: 'Basics',
            weekLabel: 'Week 1',
            tasks: [
              MilestoneTask(
                  id: '$goalId-t1', name: 'Read unit 1', done: allDone),
              MilestoneTask(
                  id: '$goalId-t2', name: 'Practise unit 1', done: allDone),
            ]),
      ];

  @override
  Future<int> generateRoadmap(String goalId) async => ++generated;
}

class _Quizzes extends QuizRepository {
  @override
  Future<List<WeakTopic>> getWeakTopics({int limit = 5}) async => const [
        WeakTopic(
            materialId: 'm',
            materialTitle: 'gate.pdf',
            unitLabel: 'Unit 3: Graphs',
            answered: 4,
            cardsReviewed: 2,
            cardsStruggling: 2,
            missRate: 0.5),
      ];
}
