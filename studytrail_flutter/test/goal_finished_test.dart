// A goal whose exams are all behind the student: no "0 days left", and Home
// stops offering catch-ups, weak spots and planning for it — the same "done"
// the home-screen widgets already showed.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:studytrail_flutter/data/repositories.dart';
import 'package:studytrail_flutter/models/models.dart';
import 'package:studytrail_flutter/screens/home_screen.dart';
import 'package:studytrail_flutter/state/stores.dart';
import 'package:studytrail_flutter/theme/app_theme.dart';

DateTime _inDays(int n) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + n);
}

void main() {
  group('Goal', () {
    test('a past exam is over, not "0 days left"', () {
      final past = Goal(id: 'g', name: 'Mid-sem', examDate: _inDays(-3));
      expect(past.examOver, isTrue);
      expect(past.daysLeft, isNull);

      final today = Goal(id: 'g', name: 'Mid-sem', examDate: _inDays(0));
      expect(today.examOver, isFalse);
      expect(today.daysLeft, 0);

      const undated = Goal(id: 'g', name: 'Mid-sem');
      expect(undated.examOver, isFalse);
      expect(undated.daysLeft, isNull);
    });
  });

  group('HomeStore.examsOver', () {
    Future<HomeStore> load(DateTime? goalDate, List<Subject> subjects) async {
      final store = HomeStore(
        profiles: const _Profiles(),
        goals: _Goals(goalDate, subjects),
        tasks: _Tasks(),
        game: const _Game(),
        roadmap: _Roadmap(),
      );
      addTearDown(store.dispose);
      await store.load();
      return store;
    }

    test('true once every dated exam has passed', () async {
      final store = await load(_inDays(-1), [
        Subject(id: 's1', name: 'DBMS', examDate: _inDays(-4)),
        Subject(id: 's2', name: 'ML', examDate: _inDays(-1)),
      ]);
      expect(store.examsOver, isTrue);
    });

    test('false while a paper is still ahead, even today', () async {
      expect(
          (await load(_inDays(-1), [
            Subject(id: 's1', name: 'DBMS', examDate: _inDays(0)),
          ]))
              .examsOver,
          isFalse);
      expect((await load(_inDays(5), const [])).examsOver, isFalse);
    });

    test('subject papers alone are enough to finish an undated goal', () async {
      final store = await load(null, [
        Subject(id: 's1', name: 'DBMS', examDate: _inDays(-2)),
      ]);
      expect(store.examsOver, isTrue);
    });

    test('false with no dates at all', () async {
      expect((await load(null, const [])).examsOver, isFalse);
    });
  });

  testWidgets('Home shows a finished goal as finished', (tester) async {
    // A narrow phone: an overflow in the finished card fails the test too.
    tester.view.physicalSize = const Size(320 * 3, 1000 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<HomeStore>(
            create: (_) => HomeStore(
                  profiles: const _Profiles(),
                  goals: _Goals(_inDays(-2), [
                    Subject(id: 's1', name: 'DBMS', examDate: _inDays(-2)),
                  ]),
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

    expect(find.text('Finished'), findsOneWidget);
    expect(find.text('Set your next target'), findsOneWidget);
    expect(find.textContaining('Exam over'), findsOneWidget);
    expect(find.text('Days left'), findsNothing);
    expect(find.text('Days left!'), findsNothing);

    // Nothing left to act on for an exam that's been sat.
    expect(find.text('Catch up'), findsNothing);
    expect(find.text('Plan day'), findsNothing);
    expect(find.text('Today’s plan'), findsNothing);
    await tester.scrollUntilVisible(find.text('Subjects'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Weak spots'), findsNothing);
    expect(find.text('Exam done'), findsOneWidget);
  });
}

class _Profiles extends ProfileRepository {
  const _Profiles();
  @override
  Future<Profile?> getMyProfile() async => null;
}

class _Goals extends GoalRepository {
  _Goals(this.examDate, this.subjects);
  final DateTime? examDate;
  final List<Subject> subjects;

  @override
  Future<List<Goal>> getGoals() async => [
        Goal(
            id: 'g',
            name: 'Semester 5 mid-sem',
            examDate: examDate,
            overallPercent: 80),
      ];
  @override
  Future<List<Subject>> getSubjects(String goalId) async => subjects;
}

class _Tasks extends TaskRepository {
  @override
  Future<List<DailyTask>> getTodayTasks() async => const [];
}

class _Game extends GamificationRepository {
  const _Game();
  @override
  Future<Streak> getStreak() async =>
      const Streak(currentStreak: 3, bestStreak: 9);
}

class _Roadmap extends RoadmapRepository {
  // Behind and with missed days: the banner would show for a live goal.
  @override
  Future<RoadmapPace> getPace(String goalId) async => const RoadmapPace(
      hasRoadmap: true, total: 40, behind: 12, overdue: 3, perDay: 2);
}

class _Quizzes extends QuizRepository {
  @override
  Future<List<WeakTopic>> getWeakTopics({int limit = 5}) async => const [
        WeakTopic(
            materialId: 'm',
            materialTitle: 'dbms.pdf',
            unitLabel: 'Unit 2: Normalisation',
            answered: 4,
            cardsReviewed: 2,
            cardsStruggling: 2,
            missRate: 0.75),
      ];
}
