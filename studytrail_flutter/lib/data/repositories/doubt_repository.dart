import '../../models/models.dart';
import '../supabase_client.dart';

/// The class doubt board. Every call is an RPC from `0023_doubts.sql` — the
/// tables have no client grants — except the AI's first answer, which is the
/// `doubt-ai` function.
class DoubtRepository {
  const DoubtRepository();

  /// [filter]: 'all', 'open' (not solved) or 'mine'.
  Future<List<DoubtSummary>> getDoubts({String filter = 'all'}) async {
    final rows = await db.rpc('get_class_doubts', params: {'p_filter': filter});
    return [
      for (final r in (rows as List))
        DoubtSummary.fromMap(Map<String, dynamic>.from(r as Map)),
    ];
  }

  Future<DoubtThread> getDoubt(String id) =>
      _thread('get_doubt', {'p_doubt': id});

  Future<DoubtThread> post({
    required String title,
    String? body,
    String? subject,
  }) =>
      _thread('post_doubt', {
        'p_title': title,
        'p_body': body,
        'p_subject': subject,
      });

  Future<DoubtThread> answer(String doubtId, String body) =>
      _thread('answer_doubt', {'p_doubt': doubtId, 'p_body': body});

  /// Toggles the caller's upvote.
  Future<DoubtThread> vote(String answerId) =>
      _thread('vote_doubt_answer', {'p_answer': answerId});

  /// The asker only; null un-marks.
  Future<DoubtThread> markSolved(String doubtId, String? answerId) =>
      _thread('mark_doubt_solved', {'p_doubt': doubtId, 'p_answer': answerId});

  Future<void> deleteDoubt(String doubtId) =>
      db.rpc('delete_doubt', params: {'p_doubt': doubtId});

  Future<void> deleteAnswer(String answerId) =>
      db.rpc('delete_doubt_answer', params: {'p_answer': answerId});

  /// [reason] is one of `spam`, `harassment`, `inappropriate`, `other`.
  Future<void> report({
    required String reason,
    String? doubtId,
    String? answerId,
  }) =>
      db.rpc('report_doubt_content', params: {
        'p_reason': reason,
        'p_doubt': doubtId,
        'p_answer': answerId,
      });

  /// The asker only, once per doubt: an answer written from their own notes.
  Future<DoubtThread> askAi(String doubtId) async {
    final res =
        await db.functions.invoke('doubt-ai', body: {'doubtId': doubtId});
    return DoubtThread.fromMap(Map<String, dynamic>.from(res.data as Map));
  }

  Future<DoubtThread> _thread(String fn, Map<String, dynamic> params) async {
    final res = await db.rpc(fn, params: params);
    return DoubtThread.fromMap(Map<String, dynamic>.from(res as Map));
  }
}
