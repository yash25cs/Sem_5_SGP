// Equal bottom-bar tabs; badge progress (the counts, the "to go" wording,
// Next up and the grid order); and the rewards that do something in the app:
// the 50:50 lifeline in quizzes and the Aurora profile card.

import 'dart:math';

import 'package:flutter/material.dart' hide MaterialType;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:studytrail_flutter/data/repositories.dart';
import 'package:studytrail_flutter/models/models.dart';
import 'package:studytrail_flutter/screens/achievements_screen.dart';
import 'package:studytrail_flutter/state/stores.dart';
import 'package:studytrail_flutter/theme/app_theme.dart';
import 'package:studytrail_flutter/widgets/nav.dart';

AchievementBadge _badge(String key,
        {bool unlocked = false, int? progress, int? goal, String? unit}) =>
    AchievementBadge(
      id: 'b-$key',
      key: key,
      name: key,
      unlocked: unlocked,
      unlockedAt: unlocked ? DateTime(2026, 10, 1) : null,
      progress: progress,
      goal: goal,
      unit: unit,
    );

void main() {
  testWidgets('every bottom-bar tab gets the same width', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(bottomNavigationBar: BottomNav(current: 1)),
    ));

    double width(String label) => tester
        .getSize(find.ancestor(
            of: find.text(label), matching: find.byType(Expanded)))
        .width;
    final widths = {
      for (final l in ['Home', 'Roadmap', 'Chat', 'Quiz', 'Profile']) width(l),
    };
    expect(widths, hasLength(1), reason: 'all five the same: $widths');
  });

  group('badge progress', () {
    test('counts read naturally, and the fraction is clamped', () {
      final streak = _badge('w', progress: 5, goal: 7, unit: 'days');
      expect(streak.progressLabel, '5 / 7 days');
      expect(streak.fraction, closeTo(5 / 7, 1e-9));
      expect(_badge('q', progress: 73, goal: 100, unit: '%').progressLabel,
          '73% / 100%');
      expect(_badge('x', progress: 1000, goal: 1000, unit: 'XP').progressLabel,
          '1,000 / 1,000 XP');
      // A yes/no badge has no count to show.
      expect(_badge('n', progress: 0, goal: 1).progressLabel, isNull);
      expect(_badge('over', progress: 9, goal: 7, unit: 'days').fraction, 1);
      expect(_badge('done', unlocked: true, progress: 2, goal: 7).fraction, 1);
    });

    test('what is left, in words', () {
      expect(toGo(_badge('a', progress: 5, goal: 7, unit: 'days')),
          '2 days to go.');
      expect(toGo(_badge('b', progress: 6, goal: 7, unit: 'days')),
          '1 day to go.');
      expect(toGo(_badge('c', progress: 73, goal: 100, unit: '%')),
          '27% to go.');
      expect(toGo(_badge('d', progress: 999, goal: 1000, unit: 'XP')),
          '1 XP to go.');
      expect(toGo(_badge('e', progress: 0, goal: 1)), isNull);
      expect(toGo(_badge('f', unlocked: true, progress: 7, goal: 7, unit: 'days')),
          isNull);
    });

    test('the store merges progress; Next up is closest first; earned lead '
        'the grid', () async {
      final store = GamificationStore(
          game: _FakeGame(), profiles: _FakeProfiles(const {}));
      addTearDown(store.dispose);
      await store.load();

      expect(store.badges.firstWhere((b) => b.key == 'week_warrior').progress,
          5);
      expect(store.nextUp.map((b) => b.key),
          ['week_warrior', 'quiz_regular', 'night_owl']);
      expect(store.badgesInOrder.first.key, 'first_step');
    });

    testWidgets('the Achievements screen shows the bars and fits a narrow '
        'phone', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 1400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ChangeNotifierProvider(
        create: (_) => GamificationStore(
            game: _FakeGame(), profiles: _FakeProfiles(const {})),
        child: MaterialApp(
            theme: AppTheme.light(), home: const AchievementsScreen()),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('of 4 badges earned', findRichText: true),
          findsOneWidget);
      expect(find.text('Next up'), findsOneWidget);
      expect(find.text('5 / 7 days'), findsOneWidget);
      expect(find.text('5/7'), findsOneWidget);
      expect(find.text('Earned'), findsOneWidget);
      expect(find.text('Not yet'), findsOneWidget);

      await tester.tap(find.text('5/7'));
      await tester.pumpAndSettle();
      expect(find.text('Your progress'), findsOneWidget);
      expect(find.text('2 days to go.'), findsOneWidget);
    });
  });

  group('50:50 lifeline', () {
    test('spends one, removes two wrong answers, once per question', () async {
      final quizzes = _FakeQuizzes(lifelines: 2);
      final store = QuizStore(quizzes: quizzes, random: Random(1));
      addTearDown(store.dispose);

      await store.start('q');
      expect(store.lifelines, 2);
      expect(store.canUseLifeline, isTrue);

      expect(await store.useLifeline(), isTrue);
      expect(store.lifelines, 1);
      expect(store.hiddenOptions, hasLength(2));
      expect(store.hiddenOptions, isNot(contains(0)),
          reason: 'the right answer always stays');
      expect(store.canUseLifeline, isFalse, reason: 'one per question');
      expect(await store.useLifeline(), isFalse);
      expect(quizzes.used, 1);

      // A removed answer can't be picked.
      store.pick(store.hiddenOptions.first);
      expect(store.answered, isFalse);
      store.pick(0);
      expect(store.answered, isTrue);
    });

    test('none held: no lifeline, and a failed count read is just zero',
        () async {
      final store = QuizStore(quizzes: _FakeQuizzes(lifelines: null));
      addTearDown(store.dispose);
      expect(await store.start('q'), isTrue);
      expect(store.lifelines, 0);
      expect(store.canUseLifeline, isFalse);
    });
  });

  test('the Aurora card follows the reward being held', () async {
    final plain = ProfileStore(
        profiles: _FakeProfiles(const {'streak_freeze'}), goals: _FakeGoals());
    final aurora = ProfileStore(
        profiles: _FakeProfiles(const {'aurora_profile'}), goals: _FakeGoals());
    addTearDown(plain.dispose);
    addTearDown(aurora.dispose);
    await plain.load();
    await aurora.load();
    expect(plain.auroraCard, isFalse);
    expect(aurora.auroraCard, isTrue);
  });
}

class _FakeGame extends GamificationRepository {
  @override
  Future<List<String>> evaluateBadges() async => const [];

  @override
  Future<List<AchievementBadge>> getBadges({bool onlyUnlocked = false}) async =>
      [
        _badge('first_step', unlocked: true),
        _badge('week_warrior'),
        _badge('quiz_regular'),
        _badge('night_owl'),
      ];

  @override
  Future<Map<String, (int, int, String?)>> getBadgeProgress() async => {
        'first_step': (1, 1, null),
        'week_warrior': (5, 7, 'days'),
        'quiz_regular': (3, 10, 'quizzes'),
        'night_owl': (0, 1, null),
      };

  @override
  Future<Streak> getStreak() async => const Streak(currentStreak: 5);

  @override
  Future<List<ActivityDay>> getRecentActivity({int days = 60}) async =>
      const [];

  @override
  Future<List<LeaderboardEntry>> getLeaderboard({int limit = 20}) async =>
      const [];
}

class _FakeProfiles extends ProfileRepository {
  const _FakeProfiles(this.held);
  final Set<String> held;

  @override
  Future<Profile?> getMyProfile() async => const Profile(id: 'me');

  @override
  Future<List<Map<String, dynamic>>> getClasses() async => const [];

  @override
  Future<Set<String>> getHeldRewards() async => held;
}

class _FakeGoals extends GoalRepository {
  @override
  Future<List<Goal>> getGoals() async => const [];
}

class _FakeQuizzes extends QuizRepository {
  _FakeQuizzes({required this.lifelines});

  /// Null: reading the count fails.
  int? lifelines;
  int used = 0;

  @override
  Future<int> lifelinesLeft() async {
    final n = lifelines;
    if (n == null) throw Exception('no network');
    return n;
  }

  @override
  Future<int> useLifeline() async {
    used++;
    lifelines = (lifelines ?? 1) - 1;
    return lifelines!;
  }

  @override
  Future<Quiz?> getQuiz(String quizId) async => Quiz(
        id: quizId,
        questions: const [
          QuizQuestion(
              id: 'q1',
              question: 'Which is right?',
              options: ['Right', 'Wrong 1', 'Wrong 2', 'Wrong 3'],
              correctIndex: 0),
        ],
      );

  @override
  Future<QuizAttempt> startAttempt(String quizId) async =>
      QuizAttempt(id: 'a', quizId: quizId);
}
