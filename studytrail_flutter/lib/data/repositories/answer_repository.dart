import 'dart:io';

import '../../config/supabase_config.dart';
import '../../models/models.dart';
import '../supabase_client.dart';

/// Long-answer practice through the `grade-answer` Edge Function
/// (`0017_answer_practice.sql`). Grades are written server-side only; this
/// reads them back.
class AnswerRepository {
  const AnswerRepository();

  /// A new question from the student's notes: for [unitLabel], else their
  /// weakest unit, else any unit they have notes for.
  Future<PracticeQuestion> newQuestion({String? unitLabel}) async {
    final res = await db.functions.invoke('grade-answer', body: {
      'action': 'question',
      'unitLabel': ?unitLabel,
    });
    return PracticeQuestion.fromMap(Map<String, dynamic>.from(res.data as Map));
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
