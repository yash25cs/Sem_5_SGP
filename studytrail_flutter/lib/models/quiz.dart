/// A row of `quizzes` plus its questions when the query embeds them.
class Quiz {
  const Quiz({
    required this.id,
    this.subjectId,
    this.title,
    this.length,
    this.timerSec = 30,
    this.questions = const [],
    this.lastAttempt,
  });

  final String id;
  final String? subjectId;
  final String? title;
  final int? length;
  final int timerSec;
  final List<QuizQuestion> questions;

  /// The most recent finished attempt, when the list query embeds it
  /// (`QuizRepository.getQuizzes`). Null for a quiz never finished.
  final QuizAttempt? lastAttempt;

  /// Finished at least once — the list offers Retake instead of Start.
  bool get attempted => lastAttempt?.completedAt != null;

  factory Quiz.fromMap(Map<String, dynamic> m) {
    final raw = m['quiz_questions'];
    final List<QuizQuestion> qs = raw is List
        ? raw.cast<Map<String, dynamic>>().map(QuizQuestion.fromMap).toList()
        : [];
    if (qs.isNotEmpty) {
      qs.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    }
    final attempts = m['quiz_attempts'];

    return Quiz(
      id: m['id'] as String,
      subjectId: m['subject_id'] as String?,
      title: m['title'] as String?,
      length: (m['length'] as num?)?.toInt(),
      timerSec: (m['timer_sec'] as num?)?.toInt() ?? 30,
      questions: qs,
      lastAttempt: attempts is List && attempts.isNotEmpty
          ? QuizAttempt.fromMap(attempts.first as Map<String, dynamic>)
          : null,
    );
  }

  /// The same quiz with [attempt] as its latest result — what the list shows
  /// straight after finishing, without fetching the list again.
  Quiz withLastAttempt(QuizAttempt attempt) => Quiz(
        id: id,
        subjectId: subjectId,
        title: title,
        length: length,
        timerSec: timerSec,
        questions: questions,
        lastAttempt: attempt,
      );
}

/// A row of `quiz_questions`. Always exactly 4 options (DB check constraint).
class QuizQuestion {
  const QuizQuestion({
    required this.id,
    required this.question,
    required this.options,
    required this.correctIndex,
    this.explanation,
    this.xpReward = 10,
    this.orderIndex = 0,
  });

  final String id;
  final String question;
  final List<String> options;
  final int correctIndex;
  final String? explanation;
  final int xpReward;
  final int orderIndex;

  bool isCorrect(int picked) => picked == correctIndex;

  factory QuizQuestion.fromMap(Map<String, dynamic> m) => QuizQuestion(
        id: m['id'] as String,
        question: (m['question'] as String?) ?? '',
        options: ((m['options'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        correctIndex: (m['correct_index'] as num?)?.toInt() ?? 0,
        explanation: m['explanation'] as String?,
        xpReward: (m['xp_reward'] as num?)?.toInt() ?? 10,
        orderIndex: (m['order_index'] as num?)?.toInt() ?? 0,
      );
}

/// A row of `quiz_attempts` — one run through a quiz.
class QuizAttempt {
  const QuizAttempt({
    required this.id,
    required this.quizId,
    this.score,
    this.total,
    this.xpEarned,
    this.completedAt,
  });

  final String id;
  final String quizId;
  final int? score;
  final int? total;
  final int? xpEarned;
  final DateTime? completedAt;

  bool get isComplete => completedAt != null;

  /// 0–1 accuracy for the results screen.
  double get accuracy =>
      (total == null || total == 0) ? 0 : (score ?? 0) / total!;

  factory QuizAttempt.fromMap(Map<String, dynamic> m) => QuizAttempt(
        id: m['id'] as String,
        quizId: m['quiz_id'] as String,
        score: (m['score'] as num?)?.toInt(),
        total: (m['total'] as num?)?.toInt(),
        xpEarned: (m['xp_earned'] as num?)?.toInt(),
        completedAt: m['completed_at'] == null
            ? null
            : DateTime.parse(m['completed_at'] as String),
      );
}
