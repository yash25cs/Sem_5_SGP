import 'enums.dart';

/// A row of `flashcard_decks`, optionally joined with `deck_stats`.
class FlashcardDeck {
  const FlashcardDeck({
    required this.id,
    required this.name,
    this.subjectId,
    this.subjectName,
    this.total = 0,
    this.due = 0,
    this.isMistakes = false,
  });

  final String id;
  final String name;
  final String? subjectId;

  /// The deck the server fills with every quiz question the student got wrong
  /// (`0021_study_tools.sql`).
  final bool isMistakes;

  /// Joined from `subjects` when the query embeds it; not a column.
  final String? subjectName;

  /// From the `deck_stats` view; 0 when the query didn't include it.
  final int total;
  final int due;

  factory FlashcardDeck.fromMap(Map<String, dynamic> m) {
    // deck_stats may arrive embedded as an object or a single-element list.
    final raw = m['deck_stats'];
    final stats = raw is List
        ? (raw.isEmpty ? null : raw.first as Map<String, dynamic>)
        : raw as Map<String, dynamic>?;
    final subject = m['subjects'];

    return FlashcardDeck(
      id: m['id'] as String,
      name: (m['name'] as String?) ?? '',
      subjectId: m['subject_id'] as String?,
      subjectName:
          subject is Map<String, dynamic> ? subject['name'] as String? : null,
      total: (stats?['total'] as num?)?.toInt() ??
          (m['total'] as num?)?.toInt() ??
          0,
      due: (stats?['due'] as num?)?.toInt() ??
          (m['due'] as num?)?.toInt() ??
          0,
      isMistakes: m['is_mistakes'] == true,
    );
  }

  Map<String, dynamic> toInsertMap() => {
        'name': name,
        if (subjectId != null) 'subject_id': subjectId,
      };

  /// Row-shaped, so [FlashcardDeck.fromMap] reads it back from the offline
  /// cache.
  Map<String, dynamic> toCacheMap() => {
        'id': id,
        'name': name,
        'subject_id': subjectId,
        'subjects': subjectName == null ? null : {'name': subjectName},
        'total': total,
        'due': due,
        'is_mistakes': isMistakes,
      };

  FlashcardDeck withDue(int due) => FlashcardDeck(
        id: id,
        name: name,
        subjectId: subjectId,
        subjectName: subjectName,
        total: total,
        due: due,
        isMistakes: isMistakes,
      );
}

/// A row of `flashcards`, including its SM-2 scheduling state.
class Flashcard {
  const Flashcard({
    required this.id,
    required this.deckId,
    required this.front,
    required this.back,
    this.unitLabel,
    this.sourceChunkId,
    this.ease = 2.5,
    this.intervalDays = 0,
    this.repetitions = 0,
    required this.dueAt,
    this.lastGrade,
  });

  final String id;
  final String deckId;
  final String front;
  final String back;
  final String? unitLabel;
  final String? sourceChunkId;
  final double ease;
  final int intervalDays;
  final int repetitions;
  final DateTime dueAt;
  final SrGrade? lastGrade;

  bool get isDue => !dueAt.isAfter(DateTime.now());

  bool get isNew => repetitions == 0;

  factory Flashcard.fromMap(Map<String, dynamic> m) => Flashcard(
        id: m['id'] as String,
        deckId: m['deck_id'] as String,
        front: (m['front'] as String?) ?? '',
        back: (m['back'] as String?) ?? '',
        unitLabel: m['unit_label'] as String?,
        sourceChunkId: m['source_chunk_id'] as String?,
        ease: (m['ease'] as num?)?.toDouble() ?? 2.5,
        intervalDays: (m['interval_days'] as num?)?.toInt() ?? 0,
        repetitions: (m['repetitions'] as num?)?.toInt() ?? 0,
        dueAt: m['due_at'] == null
            ? DateTime.now()
            : DateTime.parse(m['due_at'] as String),
        lastGrade: m['last_grade'] == null
            ? null
            : SrGrade.fromDb(m['last_grade'] as String?),
      );

  Map<String, dynamic> toInsertMap() => {
        'deck_id': deckId,
        'front': front,
        'back': back,
        if (unitLabel != null) 'unit_label': unitLabel,
        if (sourceChunkId != null) 'source_chunk_id': sourceChunkId,
      };

  /// Row-shaped, so [Flashcard.fromMap] reads it back from the offline cache.
  Map<String, dynamic> toCacheMap() => {
        'id': id,
        'deck_id': deckId,
        'front': front,
        'back': back,
        'unit_label': unitLabel,
        'source_chunk_id': sourceChunkId,
        'ease': ease,
        'interval_days': intervalDays,
        'repetitions': repetitions,
        'due_at': dueAt.toUtc().toIso8601String(),
        'last_grade': lastGrade?.db,
      };
}
