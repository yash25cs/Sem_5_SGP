/// One unit the student keeps getting wrong, from `get_weak_topics`.
///
/// Evidence is quiz answers plus reviewed flashcards; a miss is a wrong answer
/// or a card last graded "again" or "hard".
class WeakTopic {
  const WeakTopic({
    required this.materialId,
    required this.materialTitle,
    this.unitLabel,
    this.answered = 0,
    this.correct = 0,
    this.cardsReviewed = 0,
    this.cardsStruggling = 0,
    this.missRate = 0,
  });

  final String materialId;
  final String materialTitle;

  /// Null when the file has no unit headings; the whole file is the topic.
  final String? unitLabel;

  final int answered;
  final int correct;
  final int cardsReviewed;
  final int cardsStruggling;

  /// 0–1: share of the evidence that was a miss.
  final double missRate;

  String get name => unitLabel ?? materialTitle;

  /// What to show under the name, from whichever evidence exists.
  String get evidence {
    final parts = <String>[
      if (answered > 0) '$correct/$answered quiz answers right',
      if (cardsReviewed > 0)
        '$cardsStruggling of $cardsReviewed cards marked hard',
    ];
    return parts.join(' · ');
  }

  factory WeakTopic.fromMap(Map<String, dynamic> m) => WeakTopic(
        materialId: m['material_id'] as String,
        materialTitle: (m['material_title'] as String?) ?? 'Your notes',
        unitLabel: m['unit_label'] as String?,
        answered: (m['answered'] as num?)?.toInt() ?? 0,
        correct: (m['correct'] as num?)?.toInt() ?? 0,
        cardsReviewed: (m['cards_reviewed'] as num?)?.toInt() ?? 0,
        cardsStruggling: (m['cards_struggling'] as num?)?.toInt() ?? 0,
        missRate: (m['miss_rate'] as num?)?.toDouble() ?? 0,
      );
}
