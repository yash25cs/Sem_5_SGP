import 'dart:io';

import '../../config/supabase_config.dart';
import '../../models/models.dart';
import '../supabase_client.dart';

/// Long-answer practice through the `grade-answer` Edge Function
/// (`0017_answer_practice.sql`). Grades are written server-side only; this
/// reads them back.
class AnswerRepository {
  const AnswerRepository();

  /// [count] (1–5) different questions from the student's notes, written in
  /// one call: for [unitLabel], else spread over their weakest units, else
  /// over the units their notes cover.
  Future<List<PracticeQuestion>> newQuestions({
    int count = 1,
    String? unitLabel,
    AnswerKind kind = AnswerKind.theory,
    PracticeSource source = PracticeSource.all,
  }) async {
    final res = await db.functions.invoke('grade-answer', body: {
      'action': 'question',
      'count': count,
      'kind': kind.name,
      'subjectId': ?source.subjectId,
      'materialId': ?source.materialId,
      'unitLabel': ?unitLabel,
    });
    final data = Map<String, dynamic>.from(res.data as Map);
    final list = data['questions'];
    final List<PracticeQuestion> questions;
    if (list is List && list.isNotEmpty) {
      questions = [
        for (final q in list)
          PracticeQuestion.fromMap(Map<String, dynamic>.from(q as Map)),
      ];
    } else {
      // A function deployed before `count`: one question, at the top level.
      questions = [PracticeQuestion.fromMap(data)];
    }
    return [for (final q in questions) q.withSource(source)];
  }

  /// What the student can write questions from: their subjects (flagged by
  /// whether any read file is tagged to them) and each file that's been read.
  Future<PracticeSources> getSources() async {
    final subjectRows = await db.from('subjects').select('id, name').order('name');
    final fileRows = await db
        .from('materials')
        .select()
        .eq('status', IngestStatus.embedded.db)
        .order('created_at', ascending: false);
    final files = fileRows.map(StudyMaterial.fromMap).toList();
    final tagged = {for (final f in files) ?f.subjectId};
    return PracticeSources(
      subjects: [
        for (final r in subjectRows)
          (
            PracticeSource(
                subjectId: r['id'] as String, label: (r['name'] as String?) ?? ''),
            tagged.contains(r['id']),
          ),
      ],
      files: [
        for (final f in files)
          PracticeSource(materialId: f.id, label: f.displayName),
      ],
    );
  }

  Future<AnswerAttempt> grade(PracticeQuestion question, String answer) async {
    final res = await db.functions.invoke('grade-answer', body: {
      ..._questionBody(question),
      'answer': answer,
    });
    return _attempt(question, res.data, answer);
  }

  /// Grades photos of a handwritten answer, one per page (up to three). They
  /// go to the student's own folder as `answer_*`; the function reads them,
  /// grades what it reads, and deletes them.
  Future<AnswerAttempt> gradePhotos(
    PracticeQuestion question,
    List<File> pages,
  ) async {
    final uid = requireUserId;
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final bucket = db.storage.from(SupabaseConfig.materialsBucket);
    final paths = <String>[];
    try {
      for (final (i, page) in pages.indexed) {
        final dot = page.path.lastIndexOf('.');
        final ext = dot < 0 ? '.jpg' : page.path.substring(dot).toLowerCase();
        final path = '$uid/answer_${stamp}_$i$ext';
        await bucket.upload(path, page);
        paths.add(path);
      }
      final res = await db.functions.invoke('grade-answer', body: {
        ..._questionBody(question),
        'imagePaths': paths,
      });
      return _attempt(question, res.data, null);
    } catch (_) {
      // The function deletes the photos it read; if it never got that far,
      // they'd sit in storage with nothing pointing at them.
      if (paths.isNotEmpty) {
        try {
          await bucket.remove(paths);
        } catch (_) {}
      }
      rethrow;
    }
  }

  Map<String, dynamic> _questionBody(PracticeQuestion question) => {
        'action': 'grade',
        if (question.paperQuestionId != null)
          'questionId': question.paperQuestionId
        else ...{
          'question': question.text,
          'marks': question.marks,
          'unitLabel': ?question.unitLabel,
          'kind': question.kind.name,
          'subjectId': ?question.source.subjectId,
          'materialId': ?question.source.materialId,
        },
      };

  AnswerAttempt _attempt(PracticeQuestion question, Object? raw, String? sent) {
    final data = Map<String, dynamic>.from(raw as Map);
    return AnswerAttempt(
      id: data['attemptId'] as String,
      question: question.text,
      score: (data['score'] as num).toDouble(),
      maxMarks: (data['maxMarks'] as num).toDouble(),
      feedback: AnswerFeedback.fromMap(
          Map<String, dynamic>.from(data['feedback'] as Map)),
      unitLabel: question.unitLabel,
      kind: question.kind,
      // For photos, what the examiner read off the page.
      answer: sent ?? (data['answer'] as String? ?? ''),
      createdAt: DateTime.now(),
    );
  }

  Future<List<AnswerAttempt>> getAttempts({int limit = 20}) async {
    final rows = await db
        .from('answer_attempts')
        .select()
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(AnswerAttempt.fromMap).toList();
  }
}
