// Past papers and long-answer practice: parsing and store behaviour, with
// Supabase faked at the repository seam.

import 'package:flutter_test/flutter_test.dart';

import 'package:studytrail_flutter/data/repositories.dart';
import 'package:studytrail_flutter/models/models.dart';
import 'package:studytrail_flutter/state/stores.dart';

void main() {
  test('ExamTopic reads get_exam_topics', () {
    final t = ExamTopic.fromMap({
      'unit_label': 'Unit 2: Transactions',
      'times_asked': 6,
      'total_marks': 35,
      'years': [2023, 2024],
      'papers': 2,
      'example': 'Explain deadlock detection.',
    });
    expect(t.timesAsked, 6);
    expect(t.totalMarks, 35);
    expect(t.years, [2023, 2024]);
    expect(t.isOther, isFalse);
    expect(ExamTopic.fromMap({'unit_label': 'Other'}).isOther, isTrue);
  });

  test('PaperQuestion takes its year from the embedded paper', () {
    final q = PaperQuestion.fromMap({
      'id': 'q1',
      'text': 'Define ACID.',
      'marks': 5,
      'question_no': 'Q1 (a)',
      'unit_label': 'Unit 2',
      'exam_papers': {'year': 2023},
    });
    expect(q.year, 2023);
    expect(q.marks, 5);
  });

  test('AnswerAttempt reads a stored grade and its feedback', () {
    final a = AnswerAttempt.fromMap({
      'id': 'a1',
      'question': 'Explain ACID.',
      'score': 3.5,
      'max_marks': 5,
      'feedback': {
        'summary': 'Good start.',
        'strengths': ['Atomicity'],
        'missing': ['Durability'],
        'model_answer': '- A\n- C',
        'used_notes': true,
      },
      'created_at': '2026-10-01T10:00:00Z',
    });
    expect(a.fraction, 0.7);
    expect(a.feedback.missing, ['Durability']);
    expect(a.feedback.usedNotes, isTrue);
  });

  group('AnswerPracticeStore', () {
    test('a graded answer goes to the top of the history', () async {
      final answers = _FakeAnswers();
      final store = AnswerPracticeStore(answers: answers);
      addTearDown(store.dispose);

      await store.load();
      expect(await store.newQuestion(), isTrue);
      expect(store.question!.marks, 5);

      expect(await store.submit('  Atomicity means all or nothing.  '), isTrue);
      expect(answers.graded, ['Atomicity means all or nothing.']);
      expect(store.result!.score, 4);
      expect(store.history.first.id, 'new');

      store.retry();
      expect(store.result, isNull);
      expect(store.question, isNotNull, reason: 'retry keeps the question');
    });

    test('a past-paper question is used as given', () {
      final store = AnswerPracticeStore(answers: _FakeAnswers());
      addTearDown(store.dispose);
      store.use(const PracticeQuestion(
          text: 'Explain 3NF.', marks: 10, paperQuestionId: 'pq-1'));
      expect(store.question!.paperQuestionId, 'pq-1');
      expect(store.result, isNull);
    });
  });

  test('ExamPapersStore builds a mock exam and reports failures', () async {
    final store = ExamPapersStore(
        papers: const _FakePapers(), quizzes: _FakeQuizzes());
    addTearDown(store.dispose);
    await store.load();
    expect(store.topics.single.unitLabel, 'Unit 2');
    expect(await store.mockExam(), 'mock-1');
    expect(store.makingMock, isFalse);
  });
}

class _FakeAnswers extends AnswerRepository {
  final graded = <String>[];

  @override
  Future<List<AnswerAttempt>> getAttempts({int limit = 20}) async => [
        const AnswerAttempt(
            id: 'old',
            question: 'Old',
            score: 2,
            maxMarks: 5,
            feedback: AnswerFeedback()),
      ];

  @override
  Future<PracticeQuestion> newQuestion({String? unitLabel}) async =>
      const PracticeQuestion(text: 'Explain ACID.', marks: 5, unitLabel: 'Unit 2');

  @override
  Future<AnswerAttempt> grade(PracticeQuestion question, String answer) async {
    graded.add(answer);
    return AnswerAttempt(
      id: 'new',
      question: question.text,
      score: 4,
      maxMarks: question.marks,
      feedback: const AnswerFeedback(summary: 'Nearly there.'),
    );
  }
}

class _FakePapers extends ExamPaperRepository {
  const _FakePapers();

  @override
  Future<List<ExamPaper>> getPapers() async => const [
        ExamPaper(
            id: 'p1',
            title: 'DBMS 2023.pdf',
            year: 2023,
            status: 'analyzed',
            questionCount: 5,
            storagePath: 'u/paper_1.pdf'),
      ];

  @override
  Future<List<ExamTopic>> getTopics() async =>
      const [ExamTopic(unitLabel: 'Unit 2', timesAsked: 3)];
}

class _FakeQuizzes extends QuizRepository {
  @override
  Future<String> generateMockExam() async => 'mock-1';
}
