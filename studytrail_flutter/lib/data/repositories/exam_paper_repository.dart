import 'dart:io';

import '../../config/supabase_config.dart';
import '../../models/models.dart';
import '../supabase_client.dart';

/// Previous-year exam papers (`0016_exam_papers.sql`).
///
/// A paper's file lives in the same private bucket as materials, flat under the
/// student's folder with a `paper_` prefix — flat so account deletion's folder
/// sweep reaches it. It is never embedded: `analyze-paper` reads it into
/// questions instead.
class ExamPaperRepository {
  const ExamPaperRepository();

  Future<List<ExamPaper>> getPapers() async {
    final rows = await db
        .from('exam_papers')
        .select()
        .order('created_at', ascending: false);
    return rows.map(ExamPaper.fromMap).toList();
  }

  /// Uploads the file and creates its row. Removes the object again if the row
  /// can't be written, the same compensation `MaterialRepository` does.
  Future<ExamPaper> upload({
    required File file,
    required String fileName,
    int? year,
    String? goalId,
  }) async {
    final uid = requireUserId;
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final safe = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path = '$uid/paper_${stamp}_$safe';

    await db.storage.from(SupabaseConfig.materialsBucket).upload(path, file);
    try {
      final row = await db
          .from('exam_papers')
          .insert({
            'user_id': uid,
            'title': fileName,
            'storage_path': path,
            'year': ?year,
            'goal_id': ?goalId,
          })
          .select()
          .single();
      return ExamPaper.fromMap(row);
    } catch (_) {
      try {
        await db.storage.from(SupabaseConfig.materialsBucket).remove([path]);
      } catch (_) {}
      rethrow;
    }
  }

  /// Reads the paper into questions. Returns how many were found.
  Future<int> analyze(String paperId) async {
    final res = await db.functions
        .invoke('analyze-paper', body: {'paperId': paperId});
    final data = res.data;
    return data is Map && data['questions'] is int ? data['questions'] as int : 0;
  }

  /// Row first, then the file: an orphaned file costs storage, an orphaned
  /// row breaks the screen.
  Future<void> delete(ExamPaper paper) async {
    await db.from('exam_papers').delete().eq('id', paper.id);
    try {
      await db.storage
          .from(SupabaseConfig.materialsBucket)
          .remove([paper.storagePath]);
    } catch (_) {}
  }

  Future<List<ExamTopic>> getTopics() async {
    final rows = await db.rpc('get_exam_topics');
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(ExamTopic.fromMap)
        .toList();
  }

  /// Past questions on one unit ('Other' for the unmatched ones), most marks
  /// first.
  Future<List<PaperQuestion>> getQuestions(String unitLabel) async {
    var query = db
        .from('paper_questions')
        .select('id, text, question_no, marks, unit_label, exam_papers(year)');
    query = unitLabel == 'Other'
        ? query.isFilter('unit_label', null)
        : query.eq('unit_label', unitLabel);
    final rows = await query.order('marks', ascending: false, nullsFirst: false);
    return rows.map(PaperQuestion.fromMap).toList();
  }
}
