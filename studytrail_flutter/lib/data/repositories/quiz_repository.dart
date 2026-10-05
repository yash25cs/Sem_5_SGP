import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/models.dart';
import '../supabase_client.dart';

/// Quizzes, attempts, and scoring.
///
/// Scoring happens in the `finish_quiz_attempt` RPC, not here — the client
/// sends only what the student picked, and the server decides correctness
/// against `quiz_questions` so a tampered app can't award itself XP.
class QuizRepository {
  const QuizRepository();

  /// Quizzes, newest first, each with its latest finished attempt embedded —
  /// one request, not one per quiz. The `quiz_attempts.` filter, order and
  /// limit apply to the embedded rows only: a quiz never finished still comes
  /// back, with an empty list.
  Future<List<Quiz>> getQuizzes({String? subjectId}) async {
    var query = db
        .from('quizzes')
        .select('*, subjects(name), '
            'quiz_attempts(id, quiz_id, score, total, xp_earned, completed_at)')
        .not('quiz_attempts.completed_at', 'is', null);
    if (subjectId != null) query = query.eq('subject_id', subjectId);
    final rows = await query
        .order('created_at', ascending: false)
        .order('completed_at', referencedTable: 'quiz_attempts', ascending: false)
        .limit(1, referencedTable: 'quiz_attempts');
    return rows.map(Quiz.fromMap).toList();
  }

  /// A quiz with its questions, ordered. Note `correct_index` is selected —
  /// the app reveals the answer after each pick, which is the intended UX.
  Future<Quiz?> getQuiz(String quizId) async {
    final row = await db
        .from('quizzes')
        .select('*, quiz_questions(*)')
        .eq('id', quizId)
        .maybeSingle();
    return row == null ? null : Quiz.fromMap(row);
  }

  /// Opens an attempt. The returned id is what `submit` scores against.
  Future<QuizAttempt> startAttempt(String quizId) async {
    final row = await db
        .from('quiz_attempts')
        .insert({'user_id': requireUserId, 'quiz_id': quizId})
        .select()
        .single();
    return QuizAttempt.fromMap(row);
  }

  /// Scores the attempt server-side, writes `quiz_answers`, awards XP, and
  /// logs the activity — all inside the RPC.
  ///
  /// [picks] maps question id → chosen option index (0–3).
  Future<QuizAttempt> submit({
    required String attemptId,
    required Map<String, int> picks,
  }) async {
    final row = await db.rpc(
      'finish_quiz_attempt',
      params: {'attempt': attemptId, 'picks': picks},
    );
    final map = row is List
        ? row.first as Map<String, dynamic>
        : row as Map<String, dynamic>;
    return QuizAttempt.fromMap(map);
  }

  /// 50:50 lifelines bought in Rewards and not yet used (`0026`). RLS limits
  /// the rows to the caller's own.
  Future<int> lifelinesLeft() async {
    final rows = await db
        .from('reward_redemptions')
        .select('id')
        .eq('reward_key', 'fifty_fifty')
        .isFilter('consumed_at', null);
    return rows.length;
  }

  /// Spends one lifeline and returns how many are left; throws with the
  /// server's message when there are none.
  Future<int> useLifeline() async {
    final left = await db.rpc('use_quiz_lifeline');
    return (left as num).toInt();
  }

  /// Past attempts for the results/history view.
  Future<List<QuizAttempt>> getAttempts({String? quizId, int limit = 20}) async {
    var query = db.from('quiz_attempts').select().not('completed_at', 'is', null);
    if (quizId != null) query = query.eq('quiz_id', quizId);
    final rows =
        await query.order('completed_at', ascending: false).limit(limit);
    return rows.map(QuizAttempt.fromMap).toList();
  }

  /// Deletes the quiz with its questions and every attempt (FK cascades,
  /// `0002_features.sql`). XP already earned stays: it lives in
  /// `activity_log`, not on the attempt.
  Future<void> deleteQuiz(String quizId) =>
      db.from('quizzes').delete().eq('id', quizId);

  /// Asks the `generate-quiz` Edge Function to write a quiz from one material.
  /// Returns the new quiz's id.
  ///
  /// No client-side fallback exists by design: `0008_rewards.sql` revokes
  /// `insert` on `quizzes` and `quiz_questions` from `authenticated`, because a
  /// self-authored quiz with known answers would be 10 XP a question.
  ///
  /// Appends — each call is a new quiz, since `quiz_attempts` history hangs off
  /// the row.
  Future<String> generateQuiz({
    required String materialId,
    int length = 10,
  }) async {
    try {
      final res = await db.functions.invoke(
        'generate-quiz',
        body: {'materialId': materialId, 'length': length},
      );
      final data = res.data;
      if (data is Map && data['quizId'] is String) {
        return data['quizId'] as String;
      }
      final msg = data is Map ? data['message'] ?? data['error'] : null;
      throw msg is String
          ? msg
          : 'Quiz generation failed — try a different file.';
    } catch (e) {
      // The function's own message ("That file isn't yours.") is inside the
      // FunctionException; friendlyError reads it out. Wrapping it in
      // 'Error: …' showed students the raw exception instead.
      if (e is String || e is FunctionException) rethrow;
      throw 'Error: $e';
    }
  }

  /// Units the student keeps getting wrong, weakest first.
  Future<List<WeakTopic>> getWeakTopics({int limit = 5}) async {
    final rows = await db.rpc('get_weak_topics', params: {'p_limit': limit});
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(WeakTopic.fromMap)
        .toList();
  }

  /// A 15-question mock exam weighted toward the units past papers ask about
  /// most. Returns the new quiz's id.
  Future<String> generateMockExam() async {
    final res = await db.functions.invoke('generate-quiz', body: {'mock': true});
    final data = res.data;
    if (data is Map && data['quizId'] is String) return data['quizId'] as String;
    throw 'Mock exam generation failed. Try again.';
  }

  /// A quiz drawn only from the weakest units. Returns the new quiz's id.
  Future<String> generateWeakQuiz({int length = 5}) async {
    final res = await db.functions.invoke(
      'generate-quiz',
      body: {'weak': true, 'length': length},
    );
    final data = res.data;
    if (data is Map && data['quizId'] is String) return data['quizId'] as String;
    throw 'Quiz generation failed. Try again.';
  }
}
