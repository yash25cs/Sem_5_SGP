/// What sort of written question this is.
enum AnswerKind {
  /// A descriptive 5- or 10-mark answer: explain, compare, derive.
  theory,

  /// A case-based application question in lettered parts, the way an
  /// NEP 2020 outcome-based paper sets them.
  nep;

  static AnswerKind parse(Object? v) => v == 'nep' ? nep : theory;
}

/// Which of the student's notes questions are written from: everything, one
/// subject, or one file.
class PracticeSource {
  const PracticeSource({this.subjectId, this.materialId, this.label = 'All my notes'});

  final String? subjectId;
  final String? materialId;
  final String label;

  static const all = PracticeSource();

  bool get isAll => subjectId == null && materialId == null;

  @override
  bool operator ==(Object other) =>
      other is PracticeSource &&
      other.subjectId == subjectId &&
      other.materialId == materialId;

  @override
  int get hashCode => Object.hash(subjectId, materialId);
}

/// What the picker can offer: each subject (with whether it has notes yet)
/// and each file that has been read.
class PracticeSources {
  const PracticeSources({this.subjects = const [], this.files = const []});

  /// Subjects, each flagged true when a read file is tagged to it.
  final List<(PracticeSource, bool)> subjects;
  final List<PracticeSource> files;
}

/// A question's text split into its scenario and lettered parts, so a case
/// question reads as paragraphs instead of one run of text.
class QuestionLayout {
  const QuestionLayout(this.lead, this.parts);

  final String lead;
  final List<QuestionPart> parts;

  static final _label = RegExp(r'(?:^|\s)\(?([a-e])\)\s+');
  static final _marks = RegExp(r'\s*\((\d+(?:\.\d+)?)\)\s*$');

  factory QuestionLayout.parse(String text) {
    final src = text.trim();
    final hits = _label.allMatches(src).toList();
    // Parts must run a, b, c… from the start; anything else is just prose.
    var ok = hits.length >= 2;
    for (var i = 0; ok && i < hits.length; i++) {
      if (hits[i].group(1) != String.fromCharCode(97 + i)) ok = false;
    }
    if (!ok) return QuestionLayout(src, const []);

    final parts = <QuestionPart>[];
    for (var i = 0; i < hits.length; i++) {
      final end = i + 1 < hits.length ? hits[i + 1].start : src.length;
      var body = src.substring(hits[i].end, end).trim();
      String? marks;
      final m = _marks.firstMatch(body);
      if (m != null) {
        marks = m.group(1);
        body = body.substring(0, m.start).trim();
      }
      parts.add(QuestionPart(hits[i].group(1)!, body, marks));
    }
    return QuestionLayout(src.substring(0, hits.first.start).trim(), parts);
  }
}

class QuestionPart {
  const QuestionPart(this.label, this.text, this.marks);
  final String label;
  final String text;

  /// The "(2)" at the end of the part, when it had one.
  final String? marks;
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
    this.source = PracticeSource.all,
  });

  final String text;
  final double marks;
  final String? unitLabel;
  final AnswerKind kind;

  /// The notes it was written from; grading looks at the same ones.
  final PracticeSource source;

  /// Set for a past-paper question; the server then reads text and marks from
  /// that row rather than trusting these.
  final String? paperQuestionId;

  PracticeQuestion withSource(PracticeSource s) => PracticeQuestion(
        text: text,
        marks: marks,
        unitLabel: unitLabel,
        paperQuestionId: paperQuestionId,
        kind: kind,
        source: s,
      );

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
