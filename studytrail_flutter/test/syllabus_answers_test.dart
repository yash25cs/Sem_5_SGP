// A syllabus for each subject (Home), answer practice in sets of 1–5, and the
// badge sheet fitting a small phone.

import 'package:flutter/material.dart' hide MaterialType;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:studytrail_flutter/data/repositories.dart';
import 'package:studytrail_flutter/models/models.dart';
import 'package:studytrail_flutter/screens/achievements_screen.dart';
import 'package:studytrail_flutter/screens/answer_practice_screen.dart';
import 'package:studytrail_flutter/state/stores.dart';
import 'package:studytrail_flutter/theme/app_theme.dart';
import 'package:studytrail_flutter/widgets/syllabus_sheet.dart';

const _physics = Subject(id: 's1', name: 'Physics');

Future<void> _phone(WidgetTester tester, Widget app, {double height = 760}) async {
  tester.view.physicalSize = Size(360 * 3, height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

void main() {
  group('subject syllabus', () {
    test('typed text becomes the subject\'s syllabus once it has been read',
        () async {
      final materials = _FakeMaterials();
      final home = HomeStore(materials: materials);
      addTearDown(home.dispose);

      expect(await home.addSyllabusText(_physics, '  Unit 1: Kinematics  '),
          isTrue);
      expect(materials.texts, ['Unit 1: Kinematics']);
      expect(materials.read, ['m1']);
      expect(home.syllabusOf(_physics)?.isReady, isTrue);
      expect(home.readingSyllabusFor, isNull);
    });

    test('replacing removes the old one only after the new one is read',
        () async {
      final materials = _FakeMaterials();
      final home = HomeStore(materials: materials);
      addTearDown(home.dispose);
      await home.addSyllabusText(_physics, 'Unit 1: Kinematics');

      expect(await home.addSyllabusText(_physics, 'Unit 1: Optics'), isTrue);
      expect(materials.deleted, ['m1']);
      expect(home.syllabusOf(_physics)?.id, 'm2');
    });

    test('one that can\'t be read is taken back out; the old one stays',
        () async {
      final materials = _FakeMaterials();
      final home = HomeStore(materials: materials);
      addTearDown(home.dispose);
      await home.addSyllabusText(_physics, 'Unit 1: Kinematics');

      materials.failRead = true;
      expect(await home.addSyllabusText(_physics, '???'), isFalse);
      expect(home.error, isNotNull);
      expect(materials.deleted, ['m2'], reason: 'the unreadable new one');
      expect(home.syllabusOf(_physics)?.id, 'm1', reason: 'old one kept');
    });

    test('remove takes it away', () async {
      final materials = _FakeMaterials();
      final home = HomeStore(materials: materials);
      addTearDown(home.dispose);
      await home.addSyllabusText(_physics, 'Unit 1: Kinematics');

      expect(await home.removeSyllabus(_physics), isTrue);
      expect(home.syllabusOf(_physics), isNull);
      expect(materials.deleted, ['m1']);
    });

    testWidgets('the sheet offers PDF or text, and saves typed text',
        (tester) async {
      final materials = _FakeMaterials();
      final home = HomeStore(materials: materials);
      await _phone(
        tester,
        ChangeNotifierProvider<HomeStore>.value(
          value: home,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showSyllabusSheet(context, _physics),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Physics syllabus'), findsOneWidget);
      expect(find.text('Upload a PDF'), findsOneWidget);
      expect(find.text('Type or paste it'), findsOneWidget);

      await tester.tap(find.text('Type or paste it'));
      await tester.pumpAndSettle();
      // Too short to be a syllabus: Save stays off.
      await tester.enterText(find.byType(TextField), 'Unit 1');
      await tester.pump();
      await tester.tap(find.text('Save syllabus'));
      await tester.pumpAndSettle();
      expect(materials.texts, isEmpty);

      await tester.enterText(find.byType(TextField),
          'Unit 1: Kinematics\nDisplacement, velocity and acceleration.');
      await tester.pump();
      await tester.tap(find.text('Save syllabus'));
      await tester.pumpAndSettle();
      expect(materials.texts, hasLength(1));
      expect(find.textContaining('Physics syllabus added'), findsOneWidget);
    });
  });

  group('answer practice sets', () {
    test('asks for the count, walks the set, then starts over', () async {
      final answers = _FakeAnswers();
      final store = AnswerPracticeStore(answers: answers);
      addTearDown(store.dispose);

      expect(await store.newQuestions(count: 3), isTrue);
      expect(answers.asked, [3]);
      expect(store.setSize, 3);
      expect(store.position, 1);
      expect(store.hasNext, isTrue);

      expect(store.next(), isTrue);
      expect(store.question!.text, 'Question 2');
      expect(store.next(), isTrue);
      expect(store.hasNext, isFalse);
      expect(store.next(), isFalse);

      store.clearSet();
      expect(store.question, isNull);
    });

    test('never more than five', () async {
      final answers = _FakeAnswers();
      final store = AnswerPracticeStore(answers: answers);
      addTearDown(store.dispose);
      await store.newQuestions(count: 9);
      expect(answers.asked, [5]);
    });

    testWidgets('pick how many, then move through them', (tester) async {
      final answers = _FakeAnswers();
      await _phone(
        tester,
        ChangeNotifierProvider(
          create: (_) => AnswerPracticeStore(answers: answers),
          child: MaterialApp(
              theme: AppTheme.light(), home: const AnswerPracticeScreen()),
        ),
      );

      expect(find.text('How many questions?'), findsOneWidget);
      expect(find.text('Give me 3 questions'), findsOneWidget);
      await tester.tap(find.text('5'));
      await tester.pump();
      expect(find.text('Give me 5 questions'), findsOneWidget);
      await tester.tap(find.text('1'));
      await tester.pump();
      expect(find.text('Give me a question'), findsOneWidget);

      await tester.tap(find.text('2'));
      await tester.pump();
      await tester.tap(find.text('Give me 2 questions'));
      await tester.pumpAndSettle();
      expect(answers.asked, [2]);
      expect(find.text('Question 1 of 2'), findsOneWidget);

      await tester.tap(find.text('Skip to the next question'));
      await tester.pumpAndSettle();
      expect(find.text('Question 2 of 2'), findsOneWidget);
      expect(find.text('Choose new questions'), findsOneWidget);

      await tester.tap(find.text('Choose new questions'));
      await tester.pumpAndSettle();
      expect(find.text('How many questions?'), findsOneWidget);
    });

    testWidgets('theory is the default; Practical (NEP) asks for NEP',
        (tester) async {
      final answers = _FakeAnswers();
      await _phone(
        tester,
        ChangeNotifierProvider(
          create: (_) => AnswerPracticeStore(answers: answers),
          child: MaterialApp(
              theme: AppTheme.light(), home: const AnswerPracticeScreen()),
        ),
      );

      expect(find.text('Type of question'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('kind-nep')));
      await tester.pump();
      expect(find.textContaining('NEP style'), findsOneWidget);
      await tester.tap(find.text('Give me 3 questions'));
      await tester.pumpAndSettle();
      expect(answers.kinds, [AnswerKind.nep]);
    });
  });

  testWidgets('the badge sheet fits a small phone', (tester) async {
    await _phone(
      tester,
      ChangeNotifierProvider(
        create: (_) => GamificationStore(
            game: _FakeGame(), profiles: const _FakeProfiles()),
        child: MaterialApp(
            theme: AppTheme.light(), home: const AchievementsScreen()),
      ),
      height: 640,
    );
    // From Next up, near the top; the grid tile is below the fold here.
    await tester.tap(find.text('Week Warrior').first);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    // An overflow would have failed the test by now; and the button is
    // reachable.
    await tester.scrollUntilVisible(find.text('Got it'), 100,
        scrollable: find.descendant(
            of: find.byType(BottomSheet), matching: find.byType(Scrollable)));
    expect(find.text('Got it'), findsOneWidget);
    expect(find.text('2 days to go.'), findsOneWidget);
  });
}

class _FakeMaterials extends MaterialRepository {
  final texts = <String>[];
  final read = <String>[];
  final deleted = <String>[];
  bool failRead = false;
  final _syllabi = <String, StudyMaterial>{};
  StudyMaterial? _last;

  @override
  Future<StudyMaterial> addSyllabusText({
    required String subjectId,
    required String title,
    required String text,
    String? goalId,
  }) async {
    texts.add(text);
    return _last = StudyMaterial(
      id: 'm${texts.length}',
      sourceType: MaterialType.syllabusPdf,
      title: title,
      subjectId: subjectId,
    );
  }

  @override
  Future<int> requestIngest(String materialId) async {
    if (failRead) throw Exception("We couldn't read any text out of that file.");
    read.add(materialId);
    _syllabi[_last!.subjectId!] = _last!.withStatus(IngestStatus.embedded);
    return 3;
  }

  @override
  Future<Map<String, StudyMaterial>> getSyllabi() async => Map.of(_syllabi);

  @override
  Future<void> deleteMaterial(StudyMaterial material) async {
    deleted.add(material.id);
    _syllabi.removeWhere((_, m) => m.id == material.id);
  }
}

class _FakeAnswers extends AnswerRepository {
  final asked = <int>[];
  final kinds = <AnswerKind>[];

  @override
  Future<List<AnswerAttempt>> getAttempts({int limit = 20}) async => const [];

  @override
  Future<List<PracticeQuestion>> newQuestions(
      {int count = 1,
      String? unitLabel,
      AnswerKind kind = AnswerKind.theory}) async {
    asked.add(count);
    kinds.add(kind);
    return [
      for (var i = 1; i <= count; i++)
        PracticeQuestion(text: 'Question $i', marks: 5, unitLabel: 'Unit $i'),
    ];
  }
}

class _FakeGame extends GamificationRepository {
  @override
  Future<List<String>> evaluateBadges() async => const [];

  @override
  Future<List<AchievementBadge>> getBadges({bool onlyUnlocked = false}) async =>
      const [
        AchievementBadge(
            id: 'b1',
            key: 'week_warrior',
            name: 'Week Warrior',
            description: 'Maintain a 7-day streak.'),
      ];

  @override
  Future<Map<String, (int, int, String?)>> getBadgeProgress() async =>
      const {'week_warrior': (5, 7, 'days')};

  @override
  Future<Streak> getStreak() async => const Streak();

  @override
  Future<List<ActivityDay>> getRecentActivity({int days = 60}) async =>
      const [];

  @override
  Future<List<LeaderboardEntry>> getLeaderboard({int limit = 20}) async =>
      const [];
}

class _FakeProfiles extends ProfileRepository {
  const _FakeProfiles();

  @override
  Future<Profile?> getMyProfile() async => const Profile(id: 'me');
}
