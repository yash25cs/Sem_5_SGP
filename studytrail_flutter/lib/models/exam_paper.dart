/// A previous-year exam paper the student uploaded.
class ExamPaper {
  const ExamPaper({
    required this.id,
    required this.title,
    this.year,
    this.status = 'pending',
    this.questionCount = 0,
    this.error,
    required this.storagePath,
  });

  final String id;
  final String title;
  final int? year;

  /// 'pending' | 'analyzing' | 'analyzed' | 'failed'
  final String status;
  final int questionCount;
  final String? error;
  final String storagePath;

  bool get analyzed => status == 'analyzed';
  bool get failed => status == 'failed';
  bool get working => status == 'pending' || status == 'analyzing';

  ExamPaper withStatus(String status) => ExamPaper(
        id: id,
        title: title,
        year: year,
        status: status,
        questionCount: questionCount,
        error: error,
        storagePath: storagePath,
      );

  factory ExamPaper.fromMap(Map<String, dynamic> m) => ExamPaper(
        id: m['id'] as String,
        title: (m['title'] as String?) ?? 'Past paper',
        year: (m['year'] as num?)?.toInt(),
        status: (m['status'] as String?) ?? 'pending',
        questionCount: (m['question_count'] as num?)?.toInt() ?? 0,
        error: m['error'] as String?,
        storagePath: m['storage_path'] as String,
      );
}

/// A syllabus unit and how often past papers ask about it, from
/// `get_exam_topics`.
class ExamTopic {
  const ExamTopic({
    required this.unitLabel,
    this.timesAsked = 0,
    this.totalMarks = 0,
    this.years = const [],
    this.papers = 0,
    this.example,
  });

  /// 'Other' for questions that matched none of the student's units.
  final String unitLabel;
  final int timesAsked;
  final double totalMarks;
  final List<int> years;
  final int papers;

  /// The highest-marks question asked on it, as a taste.
  final String? example;

  bool get isOther => unitLabel == 'Other';

  factory ExamTopic.fromMap(Map<String, dynamic> m) => ExamTopic(
        unitLabel: (m['unit_label'] as String?) ?? 'Other',
        timesAsked: (m['times_asked'] as num?)?.toInt() ?? 0,
        totalMarks: (m['total_marks'] as num?)?.toDouble() ?? 0,
        years: [
          for (final y in (m['years'] as List? ?? const []))
            if (y is num) y.toInt(),
        ],
        papers: (m['papers'] as num?)?.toInt() ?? 0,
        example: m['example'] as String?,
      );
}

/// One question from a past paper.
class PaperQuestion {
  const PaperQuestion({
    required this.id,
    required this.text,
    this.questionNo,
    this.marks,
    this.unitLabel,
    this.year,
  });

  final String id;
  final String text;
  final String? questionNo;
  final double? marks;
  final String? unitLabel;

  /// From the paper it came from, when the query embeds it.
  final int? year;

  factory PaperQuestion.fromMap(Map<String, dynamic> m) {
    final paper = m['exam_papers'];
    return PaperQuestion(
      id: m['id'] as String,
      text: (m['text'] as String?) ?? '',
      questionNo: m['question_no'] as String?,
      marks: (m['marks'] as num?)?.toDouble(),
      unitLabel: m['unit_label'] as String?,
      year: paper is Map ? (paper['year'] as num?)?.toInt() : null,
    );
  }
}
