/// What sort of written question this is.
enum AnswerKind {
  /// A descriptive 5- or 10-mark answer: explain, compare, derive.
  theory,

  /// A case-based application question in lettered parts, the way an
  /// NEP 2020 outcome-based paper sets them.
  nep;

  static AnswerKind parse(Object? v) => v == 'nep' ? nep : theory;
}

/// A long-answer question to practise on — a past-paper question, or one
/// `grade-answer` wrote from the student's notes.
class PracticeQuestion {
  const PracticeQuestion({
    required this.text,
    required this.marks,
    this.unitLabel,
    this.paperQuestionId,
    this.kind = AnswerKind.theory,
  });

  final String text;
  final double marks;
  final String? unitLabel;
  final AnswerKind kind;

  /// Set for a past-paper question; the server then reads text and marks from
  /// that row rather than trusting these.
  final String? paperQuestionId;

  factory PracticeQuestion.fromMap(Map<String, dynamic> m) => PracticeQuestion(
        text: (m['question'] as String?) ?? '',
        marks: (m['marks'] as num?)?.toDouble() ?? 5,
        unitLabel: m['unitLabel'] as String?,
        kind: AnswerKind.parse(m['kind']),
      );
}

/// Examiner-style feedback on one written answer.
class AnswerFeedback {
  const AnswerFeedback({
    this.summary = '',
    this.strengths = const [],
    this.missing = const [],
    this.modelAnswer = '',
    this.usedNotes = false,
    this.fromPhoto = false,
  });

  final String summary;
  final List<String> strengths;
  final List<String> missing;
  final String modelAnswer;

  /// False when nothing the student uploaded covered the question, so the
  /// grade leaned on general knowledge.
  final bool usedNotes;

  /// True when the answer was a photo of handwriting; the attempt's `answer`
  /// is then what the examiner read from it.
  final bool fromPhoto;

  static List<String> _list(Object? v) =>
      [for (final s in (v as List? ?? const [])) if (s is String) s];

  factory AnswerFeedback.fromMap(Map<String, dynamic> m) => AnswerFeedback(
        summary: (m['summary'] as String?) ?? '',
        strengths: _list(m['strengths']),
        missing: _list(m['missing']),
        modelAnswer: (m['model_answer'] as String?) ?? '',
        usedNotes: m['used_notes'] == true,
        fromPhoto: m['from_photo'] == true,
      );
}

/// A graded answer, fresh from `grade-answer` or from history.
class AnswerAttempt {
  const AnswerAttempt({
    required this.id,
    required this.question,
    required this.score,
    required this.maxMarks,
    required this.feedback,
    this.unitLabel,
    this.answer = '',
    this.createdAt,
    this.kind = AnswerKind.theory,
  });

  final String id;
  final String question;
  final double score;
  final double maxMarks;
  final AnswerFeedback feedback;
  final String? unitLabel;
  final String answer;
  final DateTime? createdAt;
  final AnswerKind kind;

  double get fraction => maxMarks <= 0 ? 0 : score / maxMarks;

  factory AnswerAttempt.fromMap(Map<String, dynamic> m) => AnswerAttempt(
        id: m['id'] as String,
        question: (m['question'] as String?) ?? '',
        score: (m['score'] as num?)?.toDouble() ?? 0,
        maxMarks: (m['max_marks'] as num?)?.toDouble() ?? 5,
        feedback: AnswerFeedback.fromMap(
            Map<String, dynamic>.from((m['feedback'] as Map?) ?? const {})),
        unitLabel: m['unit_label'] as String?,
        answer: (m['answer'] as String?) ?? '',
        kind: AnswerKind.parse(m['kind']),
        createdAt: m['created_at'] == null
            ? null
            : DateTime.parse(m['created_at'] as String),
      );
}
