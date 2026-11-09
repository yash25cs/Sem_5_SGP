/// A row of `goal_results` (0037): how a finished goal's exam went.
class GoalResult {
  const GoalResult({
    required this.goalId,
    this.marks,
    this.outOf,
    this.feeling,
    this.hardUnits = const [],
  });

  final String goalId;
  final double? marks;
  final double? outOf;

  /// 1 tough · 2 okay · 3 good · 4 great.
  final int? feeling;

  /// Units that felt hard — the next goal's roadmap gives them more time.
  final List<String> hardUnits;

  static const feelings = ['Tough', 'Okay', 'Good', 'Great'];

  String? get feelingLabel => feeling == null || feeling! < 1 || feeling! > 4
      ? null
      : feelings[feeling! - 1];

  /// 0–1, when both numbers were given.
  double? get score =>
      marks == null || outOf == null || outOf == 0 ? null : marks! / outOf!;

  /// "62/80", or "62" without a total; null without marks.
  String? get marksLabel {
    if (marks == null) return null;
    String n(double v) =>
        v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
    return outOf == null ? n(marks!) : '${n(marks!)}/${n(outOf!)}';
  }

  factory GoalResult.fromMap(Map<String, dynamic> m) => GoalResult(
        goalId: m['goal_id'] as String,
        marks: (m['marks'] as num?)?.toDouble(),
        outOf: (m['out_of'] as num?)?.toDouble(),
        feeling: (m['feeling'] as num?)?.toInt(),
        hardUnits: [
          for (final u in (m['hard_units'] as List? ?? const []))
            if (u is String && u.trim().isNotEmpty) u.trim(),
        ],
      );

  /// For an upsert on `goal_id`; `user_id` defaults to the caller.
  Map<String, dynamic> toUpsertMap() => {
        'goal_id': goalId,
        'marks': marks,
        'out_of': outOf,
        'feeling': feeling,
        'hard_units': hardUnits,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
}

/// A one-page revision sheet from `revision-sheet`: titled sections of
/// bullets.
class RevisionSheet {
  const RevisionSheet({
    required this.title,
    this.unit,
    required this.sections,
    this.pastQuestions = 0,
  });

  /// The material's title.
  final String title;

  /// The unit it covers; null for the whole file.
  final String? unit;
  final List<(String, List<String>)> sections;

  /// How many of the student's past paper questions steered it.
  final int pastQuestions;

  /// Reads "## Heading" lines and "• bullet" lines. Lines before the first
  /// heading go under "Notes"; a bullet's marker ("•", "-", "*") is dropped.
  factory RevisionSheet.parse(String text,
      {required String title, String? unit, int pastQuestions = 0}) {
    final sections = <(String, List<String>)>[];
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#')) {
        final heading = line.replaceFirst(RegExp(r'^#+\s*'), '').trim();
        if (heading.isNotEmpty) sections.add((heading, <String>[]));
        continue;
      }
      final item = line.replaceFirst(RegExp(r'^([•\-*]|\d+[.)])\s*'), '');
      if (item.isEmpty) continue;
      if (sections.isEmpty) sections.add(('Notes', <String>[]));
      sections.last.$2.add(item.replaceAll('**', ''));
    }
    return RevisionSheet(
      title: title,
      unit: unit,
      sections: [
        for (final s in sections)
          if (s.$2.isNotEmpty) s,
      ],
      pastQuestions: pastQuestions,
    );
  }

  /// Plain text for copying or sharing.
  String get asText => [
        unit == null ? title : '$unit — $title',
        for (final (heading, items) in sections) ...[
          '',
          heading.toUpperCase(),
          for (final i in items) '• $i',
        ],
      ].join('\n');
}
