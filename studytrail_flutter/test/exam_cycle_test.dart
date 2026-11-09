// The exam cycle around a goal: the final stretch before a paper, a one-page
// revision sheet, "How did it go?" afterwards, Do Not Disturb and noise in a
// focus block, and where the focused time went.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:studytrail_flutter/data/repositories.dart';
import 'package:studytrail_flutter/models/models.dart';
import 'package:studytrail_flutter/screens/home_screen.dart';
import 'package:studytrail_flutter/screens/revision_sheet_screen.dart';
import 'package:studytrail_flutter/services/focus_extras.dart';
import 'package:studytrail_flutter/services/notification_service.dart';
import 'package:studytrail_flutter/state/stores.dart';
import 'package:studytrail_flutter/theme/app_theme.dart';
import 'package:studytrail_flutter/widgets/goal_result_sheet.dart';

DateTime _inDays(int n) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + n);
}

HomeStore _home(List<Goal> goals, List<Subject> subjects,
        {Map<String, GoalResult> results = const {},
        List<StudySession> sessions = const []}) =>
    HomeStore(
      profiles: const _Profiles(),
      goals: _Goals(goals, subjects, results),
      tasks: _Tasks(),
      game: _Game(sessions),
      roadmap: _Roadmap(),
      cards: _Cards(),
      papers: _Papers(),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Final stretch', () {
    final dbms = Goal(id: 'g', name: 'Sem 5', examDate: _inDays(20));
    final paper =
        Subject(id: 's1', name: 'DBMS', goalId: 'g', examDate: _inDays(1));

    test('a paper tomorrow starts it, with due cards and most-asked units',
        () async {
      final store = _home([dbms], [paper]);
      addTearDown(store.dispose);
      await store.load();
      final s = store.finalStretch!;
      expect(s.paper, 'DBMS');
      expect(s.when, 'tomorrow');
      expect(store.dueCards, 3);
      expect(store.askedMost.map((t) => t.unitLabel),
          ['Normalisation', 'Transactions']);
    });

    test(
        'Plan day gives no new topics for it, but still plans the other '
        'goal', () async {
      final only = _home([dbms], [paper]);
      addTearDown(only.dispose);
      await only.load();
      expect(await only.planDayFromRoadmap(), PlanDayResult.revising);

      final gate = Goal(
          id: 'gate', name: 'GATE', examDate: _inDays(40), isActive: false);
      final both = _home([dbms, gate], [paper]);
      addTearDown(both.dispose);
      await both.load();
      expect(await both.planDayFromRoadmap(), PlanDayResult.added);
      expect(both.tasks.map((t) => t.goalId).toSet(), {'gate'});
    });

    test('three days out, nothing changes', () async {
      final store = _home([
        dbms
      ], [
        Subject(id: 's1', name: 'DBMS', goalId: 'g', examDate: _inDays(3)),
      ]);
      addTearDown(store.dispose);
      await store.load();
      expect(store.finalStretch, isNull);
    });

    testWidgets('Home shows the card on a narrow phone, and no catch-up',
        (tester) async {
      await _pumpHome(tester, _home([dbms], [paper]));
      expect(find.text('Final stretch: DBMS tomorrow'), findsOneWidget);
      expect(find.text('Review 3 due cards'), findsOneWidget);
      expect(find.text('Most asked: Normalisation'), findsOneWidget);
      expect(find.text('Read a revision sheet'), findsOneWidget);
      expect(find.text('Catch up'), findsNothing);
    });
  });

  group('Revision sheet', () {
    const text = '## Key ideas\n• Normal forms cut redundancy\n'
        '- **BCNF** is stricter than 3NF\n\n## Definitions\n'
        '• Functional dependency: X decides Y\n## Empty\n';

    test('reads headings and bullets, and drops empty sections', () {
      final sheet = RevisionSheet.parse(text,
          title: 'dbms.pdf', unit: 'Normalisation', pastQuestions: 2);
      expect(sheet.sections.map((s) => s.$1), ['Key ideas', 'Definitions']);
      expect(sheet.sections.first.$2,
          ['Normal forms cut redundancy', 'BCNF is stricter than 3NF']);
      expect(sheet.asText, startsWith('Normalisation — dbms.pdf'));
    });

    test('a Latin sheet becomes a PDF; Hindi is shared as text', () async {
      final sheet = RevisionSheet.parse(text, title: 'dbms.pdf');
      expect(revisionSheetPrintable(sheet), isTrue);
      final bytes = await revisionSheetPdf(sheet);
      expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');

      final hindi = RevisionSheet.parse('## मुख्य बातें\n• सामान्यीकरण',
          title: 'dbms.pdf');
      expect(revisionSheetPrintable(hindi), isFalse);
    });

    testWidgets('the screen shows the sections from the function',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: RevisionSheetScreen(
            materialId: 'm', unitLabel: 'Normalisation', materials: _Sheets()),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Normalisation'), findsOneWidget);
      expect(find.text('Key ideas'), findsOneWidget);
      expect(find.text('Save as PDF'), findsOneWidget);
      expect(find.text('Shaped by 2 past questions'), findsOneWidget);
    });
  });

  group('How did it go?', () {
    final over = Goal(
        id: 'g', name: 'Mid-sem', examDate: _inDays(-3), overallPercent: 70);
    final subjects = [
      Subject(id: 's1', name: 'DBMS', goalId: 'g', examDate: _inDays(-3)),
    ];
    final sessions = [
      StudySession(
          id: 'a', subjectId: 's1', focusedMin: 50, sessionDate: _inDays(-5)),
      StudySession(
          id: 'b',
          subjectId: 'other',
          focusedMin: 25,
          sessionDate: _inDays(-5)),
    ];

    test('the result reads as marks and a percentage', () {
      const r = GoalResult(goalId: 'g', marks: 62, outOf: 80, feeling: 3);
      expect(r.marksLabel, '62/80');
      expect(r.score, closeTo(0.775, 0.001));
      expect(r.feelingLabel, 'Good');
    });

    testWidgets('a finished goal asks, then shows the score and focus time',
        (tester) async {
      await _pumpHome(tester, _home([over], subjects, sessions: sessions));
      expect(find.textContaining('How did it go?'), findsOneWidget);
      expect(find.text('50m'), findsOneWidget); // only DBMS's block

      await _pumpHome(
          tester,
          _home([over], subjects,
              sessions: sessions,
              results: {
                'g': const GoalResult(
                    goalId: 'g',
                    marks: 62,
                    outOf: 80,
                    feeling: 3,
                    hardUnits: ['SQL joins']),
              }));
      expect(find.text('62/80'), findsOneWidget);
      expect(find.text('Scored'), findsOneWidget);
      expect(find.text('78% · Felt good · Hard: SQL joins'), findsOneWidget);
    });

    testWidgets('the sheet checks the marks and returns what was picked',
        (tester) async {
      GoalResult? saved;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async =>
                  saved = await showModalBottomSheet<GoalResult>(
                context: context,
                isScrollControlled: true,
                builder: (_) => GoalResultSheet(
                    goal: over, suggestions: const ['DBMS', 'SQL joins']),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Marks'), '90');
      await tester.enterText(find.widgetWithText(TextField, 'Out of'), '80');
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(find.text("Marks can't be more than the total."), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Marks'), '62');
      await tester.tap(find.text('Good'));
      await tester.tap(find.text('SQL joins'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved?.marks, 62);
      expect(saved?.outOf, 80);
      expect(saved?.feeling, 3);
      expect(saved?.hardUnits, ['SQL joins']);
    });
  });

  group('Focus extras', () {
    testWidgets(
        'silence follows the locked block; sound plays only while running',
        (tester) async {
      final extras = _FakeExtras(access: true);
      final store = PomodoroStore(
          game: _Game(const []),
          goals: _Goals(const [], const [], const {}),
          notifications: _Notices(),
          extras: extras);
      addTearDown(store.dispose);

      expect(await store.setSilence(true), isTrue);
      await store.setSound(FocusSound.pink);
      store.start();
      await tester.pump();
      expect(extras.dnd, isTrue);
      expect(extras.playing, FocusSound.pink);

      // One tick first: a block paused at its full length was never begun.
      await tester.pump(const Duration(seconds: 1));
      store.pause();
      await tester.pump();
      expect(extras.playing, FocusSound.off);
      expect(extras.dnd, isTrue, reason: 'a paused block is still locked');

      store.endEarly();
      await tester.pump();
      expect(extras.dnd, isFalse);
    });

    test("silence can't be turned on without the phone's permission", () async {
      final store = PomodoroStore(
          game: _Game(const []),
          goals: _Goals(const [], const [], const {}),
          notifications: _Notices(),
          extras: _FakeExtras(access: false));
      addTearDown(store.dispose);
      expect(await store.setSilence(true), isFalse);
      expect(store.silence, isFalse);
    });
  });

  group('Where the time went', () {
    test('by subject, by goal, by time of day, and a quiet goal', () {
      final now = DateTime.now();
      DateTime at(int daysAgo, int hour) =>
          DateTime(now.year, now.month, now.day - daysAgo, hour);
      final goals = [
        Goal(id: 'a', name: 'Sem 5', examDate: _inDays(20)),
        Goal(id: 'b', name: 'GATE', examDate: _inDays(60)),
      ];
      final subjects = [
        const Subject(id: 's1', name: 'DBMS', goalId: 'a'),
        const Subject(id: 's2', name: 'Graphs', goalId: 'b'),
      ];
      StudySession s(String sub, int min, DateTime start) => StudySession(
          id: '$sub$start',
          subjectId: sub,
          focusedMin: min,
          sessionDate: start,
          startedAt: start);
      final f = FocusBreakdown.from([
        s('s1', 50, at(1, 19)),
        s('s1', 25, at(2, 20)),
        s('s2', 25, at(12, 9)),
        s('s1', 25, at(40, 19)), // older than 30 days
      ], subjects, goals, now);

      expect(f.totalMinutes, 100);
      expect(f.bySubject, [('DBMS', 75), ('Graphs', 25)]);
      expect(f.byGoal, [('Sem 5', 75), ('GATE', 25)]);
      expect(f.bestPart, DayPart.evening);
      expect(f.bestShare, closeTo(0.75, 0.001));
      expect(f.quietGoals, ['GATE']);
    });
  });
}

Future<void> _pumpHome(WidgetTester tester, HomeStore store) async {
  tester.view.physicalSize = const Size(320 * 3, 1200 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    key: UniqueKey(),
    providers: [
      ChangeNotifierProvider<HomeStore>.value(value: store),
      ChangeNotifierProvider<WeakSpotsStore>(
          create: (_) => WeakSpotsStore(quizzes: _Quizzes())),
    ],
    child: MaterialApp(
        theme: AppTheme.light(), home: const Scaffold(body: HomeScreen())),
  ));
  await tester.pumpAndSettle();
}

class _Profiles extends ProfileRepository {
  const _Profiles();
  @override
  Future<Profile?> getMyProfile() async => null;
}

class _Goals extends GoalRepository {
  _Goals(this.goals, this.subjects, this.results);
  final List<Goal> goals;
  final List<Subject> subjects;
  final Map<String, GoalResult> results;

  @override
  Future<List<Goal>> getGoals() async => goals;
  @override
  Future<Goal?> getActiveGoal() async =>
      goals.where((g) => g.isActive).firstOrNull;
  @override
  Future<List<Subject>> getSubjects(String goalId) async =>
      subjects.where((s) => s.goalId == goalId).toList();
  @override
  Future<List<Subject>> getAllSubjects() async => subjects;
  @override
  Future<Map<String, GoalResult>> getResults() async => results;
}

class _Tasks extends TaskRepository {
  @override
  Future<List<DailyTask>> getTodayTasks() async => const [];
  @override
  Future<Set<String>> getScheduledMilestoneTaskIds(String goalId) async => {};
  @override
  Future<List<DailyTask>> createTasksFromRoadmap({
    required String goalId,
    required List<MilestoneTask> tasks,
    DateTime? scheduledDate,
  }) async =>
      [
        for (final t in tasks)
          DailyTask(
              id: '$goalId-${t.id}',
              title: t.name,
              milestoneTaskId: t.id,
              scheduledDate: DateTime.now(),
              goalId: goalId),
      ];
}

class _Game extends GamificationRepository {
  _Game(this.sessions);
  final List<StudySession> sessions;
  @override
  Future<Streak> getStreak() async => const Streak(bestStreak: 4);
  @override
  Future<List<StudySession>> getStudySessions({int limit = 50}) async =>
      sessions;
}

class _Roadmap extends RoadmapRepository {
  @override
  Future<RoadmapPace> getPace(String goalId) async => const RoadmapPace(
      hasRoadmap: true, total: 20, behind: 6, overdue: 2, perDay: 2);
  @override
  Future<List<Milestone>> getMilestones(String goalId) async => [
        Milestone(
            id: '$goalId-w1',
            title: 'Basics',
            weekLabel: 'Week 1',
            tasks: [MilestoneTask(id: '$goalId-t1', name: 'Read unit 1')]),
      ];
}

class _Cards extends FlashcardRepository {
  @override
  Future<List<Flashcard>> getDueCards({String? deckId, int limit = 40}) async =>
      [
        for (var i = 0; i < 3; i++)
          Flashcard(
              id: 'c$i',
              deckId: 'd',
              front: 'f',
              back: 'b',
              dueAt: DateTime.now()),
      ];
}

class _Papers extends ExamPaperRepository {
  @override
  Future<List<ExamTopic>> getTopics() async => const [
        ExamTopic(unitLabel: 'Transactions', timesAsked: 3),
        ExamTopic(unitLabel: 'Other', timesAsked: 9),
        ExamTopic(unitLabel: 'Normalisation', timesAsked: 5),
      ];
}

class _Quizzes extends QuizRepository {
  @override
  Future<List<WeakTopic>> getWeakTopics({int limit = 5}) async => const [];
}

class _Sheets extends MaterialRepository {
  @override
  Future<RevisionSheet> requestRevisionSheet(String materialId,
          {String? unitLabel}) async =>
      RevisionSheet.parse('## Key ideas\n• Normal forms cut redundancy',
          title: 'dbms.pdf', unit: unitLabel, pastQuestions: 2);
}

class _Notices extends NotificationService {
  _Notices() : super.forTesting();
  @override
  Future<void> requestPermissions() async {}
  @override
  Future<void> showFocusSession({
    required String title,
    required String body,
    DateTime? endsAt,
    int totalSeconds = 0,
    int secondsLeft = 0,
  }) async {}
  @override
  Future<void> cancelFocusSession() async {}
}

class _FakeExtras extends FocusExtras {
  _FakeExtras({required this.access});
  final bool access;
  bool dnd = false;
  FocusSound playing = FocusSound.off;

  @override
  Future<bool> hasDndAccess() async => access;
  @override
  Future<void> setDnd(bool on) async => dnd = on;
  @override
  Future<void> playSound(FocusSound sound) async => playing = sound;
}
