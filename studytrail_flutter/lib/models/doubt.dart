/// The class doubt board (`0023_doubts.sql`).
library;

String _initial(String? initial, String name) {
  final i = initial?.trim() ?? '';
  if (i.isNotEmpty) return i[0].toUpperCase();
  return name.isEmpty ? 'S' : name[0].toUpperCase();
}

/// A doubt as the board lists it.
class DoubtSummary {
  const DoubtSummary({
    required this.id,
    required this.title,
    required this.author,
    required this.initial,
    required this.createdAt,
    this.subject,
    this.solved = false,
    this.isMine = false,
    this.answers = 0,
    this.hasAi = false,
  });

  final String id;
  final String title;
  final String? subject;
  final String author;
  final String initial;
  final DateTime createdAt;
  final bool solved;
  final bool isMine;
  final int answers;
  final bool hasAi;

  factory DoubtSummary.fromMap(Map<String, dynamic> m) {
    final author = (m['author'] as String?) ?? 'Student';
    return DoubtSummary(
      id: m['id'] as String,
      title: (m['title'] as String?) ?? '',
      subject: m['subject'] as String?,
      author: author,
      initial: _initial(m['avatar_initial'] as String?, author),
      createdAt: DateTime.parse(m['created_at'] as String),
      solved: m['solved'] == true,
      isMine: m['is_mine'] == true,
      answers: (m['answers'] as num?)?.toInt() ?? 0,
      hasAi: m['has_ai'] == true,
    );
  }
}

class DoubtAnswer {
  const DoubtAnswer({
    required this.id,
    required this.body,
    required this.author,
    required this.initial,
    required this.userId,
    required this.createdAt,
    this.isAi = false,
    this.isMine = false,
    this.votes = 0,
    this.voted = false,
  });

  final String id;
  final String body;

  /// For an AI answer, the asker whose notes it was written from.
  final String author;
  final String initial;
  final String userId;
  final DateTime createdAt;
  final bool isAi;
  final bool isMine;
  final int votes;
  final bool voted;

  factory DoubtAnswer.fromMap(Map<String, dynamic> m) {
    final author = (m['author'] as String?) ?? 'Student';
    return DoubtAnswer(
      id: m['id'] as String,
      body: (m['body'] as String?) ?? '',
      author: author,
      initial: _initial(m['avatar_initial'] as String?, author),
      userId: m['user_id'] as String,
      createdAt: DateTime.parse(m['created_at'] as String),
      isAi: m['is_ai'] == true,
      isMine: m['is_mine'] == true,
      votes: (m['votes'] as num?)?.toInt() ?? 0,
      voted: m['voted'] == true,
    );
  }
}

/// One doubt with its answers — the one that solved it first, then by votes.
class DoubtThread {
  const DoubtThread({
    required this.id,
    required this.title,
    required this.author,
    required this.initial,
    required this.userId,
    required this.createdAt,
    this.body,
    this.subject,
    this.isMine = false,
    this.solvedAnswerId,
    this.answers = const [],
  });

  final String id;
  final String title;
  final String? body;
  final String? subject;
  final String author;
  final String initial;
  final String userId;
  final DateTime createdAt;
  final bool isMine;
  final String? solvedAnswerId;
  final List<DoubtAnswer> answers;

  bool get solved => solvedAnswerId != null;
  bool get hasAi => answers.any((a) => a.isAi);

  factory DoubtThread.fromMap(Map<String, dynamic> m) {
    final author = (m['author'] as String?) ?? 'Student';
    return DoubtThread(
      id: m['id'] as String,
      title: (m['title'] as String?) ?? '',
      body: m['body'] as String?,
      subject: m['subject'] as String?,
      author: author,
      initial: _initial(m['avatar_initial'] as String?, author),
      userId: m['user_id'] as String,
      createdAt: DateTime.parse(m['created_at'] as String),
      isMine: m['is_mine'] == true,
      solvedAnswerId: m['solved_answer_id'] as String?,
      answers: [
        for (final a in (m['answers'] as List? ?? const []))
          DoubtAnswer.fromMap(Map<String, dynamic>.from(a as Map)),
      ],
    );
  }
}
