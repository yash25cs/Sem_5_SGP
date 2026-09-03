import '../../models/models.dart';
import '../supabase_client.dart';

/// Quizzes, attempts, and scoring.
///
/// Scoring happens in the `finish_quiz_attempt` RPC, not here — the client
/// sends only what the student picked, and the server decides correctness
/// against `quiz_questions` so a tampered app can't award itself XP.
class QuizRepository {
  const QuizRepository();

  Future<List<Quiz>> getQuizzes({String? subjectId}) async {
    var query = db.from('quizzes').select('*, subjects(name)');
    if (subjectId != null) query = query.eq('subject_id', subjectId);
    final rows = await query.order('created_at', ascending: false);
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

  /// Past attempts for the results/history view.
  Future<List<QuizAttempt>> getAttempts({String? quizId, int limit = 20}) async {
    var query = db.from('quiz_attempts').select().not('completed_at', 'is', null);
    if (quizId != null) query = query.eq('quiz_id', quizId);
    final rows =
        await query.order('completed_at', ascending: false).limit(limit);
    return rows.map(QuizAttempt.fromMap).toList();
  }

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
  Future<String?> generateQuiz({
    required String materialId,
    int length = 10,
  }) async {
    final res = await db.functions.invoke(
      'generate-quiz',
      body: {'materialId': materialId, 'length': length},
    );
    final data = res.data;
    if (data is Map && data['quizId'] is String) return data['quizId'] as String;
    return null;
  }
}
