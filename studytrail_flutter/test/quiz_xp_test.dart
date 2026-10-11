// Quiz XP is paid on a quiz's first finished attempt only (0032); a retake is
// practice, and the quiz screen says so instead of showing "+0 XP". The rule
// itself is the server's — checked in a rolled-back transaction when 0032 was
// written — so these cover what the app shows.

import 'package:flutter/material.dart' hide MaterialType;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:studytrail_flutter/data/repositories.dart';
import 'package:studytrail_flutter/models/models.dart';
import 'package:studytrail_flutter/screens/quiz_screen.dart';
import 'package:studytrail_flutter/state/stores.dart';
import 'package:studytrail_flutter/theme/app_theme.dart';

void main() {
  test('xp_paid_at marks a quiz whose XP is spent', () {
    expect(Quiz.fromMap({'id': 'q'}).practiceOnly, isFalse);
    expect(Quiz.fromMap({'id': 'q', 'xp_paid_at': '2026-10-11T10:00:00Z'})
        .practiceOnly, isTrue);
    final finished = const Quiz(id: 'q').withLastAttempt(
        QuizAttempt(id: 'a', quizId: 'q', completedAt: DateTime(2026)));
    expect(finished.practiceOnly, isTrue);
  });

  for (final (label, paid) in [('first attempt', false), ('retake', true)]) {
    testWidgets('$label: the chip and the results say what it earned',
        (tester) async {
      final repo = _Quizzes(paid: paid);
      tester.view.physicalSize = const Size(360 * 3, 860 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<QuizStore>(
              create: (_) => QuizStore(quizzes: repo)),
          ChangeNotifierProvider<WeakSpotsStore>(
              create: (_) => WeakSpotsStore(quizzes: repo)),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const QuizScreen()),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Optics'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(paid ? 'Retake' : 'Start quiz'));
      await tester.pumpAndSettle();
      expect(find.text(paid ? 'Practice' : '+10 XP'), findsOneWidget);

      await tester.tap(find.text('Lens'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('See results'));
      await tester.pumpAndSettle();
      if (paid) {
        expect(find.text('No XP on a retake'), findsOneWidget);
        expect(find.text('XP earned'), findsNothing);
      } else {
        expect(find.text('+10'), findsOneWidget);
        expect(find.text('XP earned'), findsOneWidget);
      }
    });
  }
}

class _Quizzes extends QuizRepository {
  _Quizzes({required this.paid});
  final bool paid;

  @override
  Future<List<Quiz>> getQuizzes({String? subjectId}) async => [
        Quiz(
          id: 'qa',
          title: 'Optics',
          length: 1,
          xpPaid: paid,
          lastAttempt: paid
              ? QuizAttempt(
                  id: 'a0',
                  quizId: 'qa',
                  score: 1,
                  total: 1,
                  completedAt: DateTime.now())
              : null,
        ),
      ];

  @override
  Future<Quiz?> getQuiz(String quizId) async => Quiz(
        id: quizId,
        title: 'Optics',
        xpPaid: paid,
        questions: const [
          QuizQuestion(
              id: 'q1',
              question: 'What bends light?',
              options: ['Lens', 'Rock', 'Wood', 'Cloth'],
              correctIndex: 0),
        ],
      );

  @override
  Future<QuizAttempt> startAttempt(String quizId) async =>
      QuizAttempt(id: 'new', quizId: quizId);

  @override
  Future<int> lifelinesLeft() async => 0;

  @override
  Future<QuizAttempt> submit({
    required String attemptId,
    required Map<String, int> picks,
  }) async =>
      QuizAttempt(
        id: attemptId,
        quizId: 'qa',
        score: 1,
        total: 1,
        xpEarned: paid ? 0 : 10,
        completedAt: DateTime.now(),
      );

  @override
  Future<List<WeakTopic>> getWeakTopics({int limit = 5}) async => const [];
}
