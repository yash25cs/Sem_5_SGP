/// Dart mirrors of the Postgres enums in `supabase/migrations/0001_init_schema.sql`.
///
/// Each enum knows its exact DB spelling so rows round-trip losslessly.
/// `fromDb` falls back to a sensible default rather than throwing — a value
/// added server-side shouldn't crash an older build.
library;

enum Pace {
  relaxed('relaxed', 'Relaxed'),
  steady('steady', 'Steady'),
  intense('intense', 'Intense');

  const Pace(this.db, this.label);
  final String db;
  final String label;

  static Pace fromDb(String? v) =>
      Pace.values.firstWhere((e) => e.db == v, orElse: () => Pace.steady);

  /// Study time a day each preset stands for, as the goal form shows it.
  int get minutes => switch (this) {
        relaxed => 60,
        steady => 120,
        intense => 240,
      };

  /// The preset closest to a custom [minutes] a day, kept in `goals.pace` so
  /// anything that only reads pace still gets a sensible answer.
  static Pace nearest(int minutes) => minutes <= 90
      ? relaxed
      : minutes <= 180
          ? steady
          : intense;
}

/// 90 → "1.5 hrs", 45 → "45 min", 60 → "1 hr".
String formatStudyTime(int minutes) {
  if (minutes < 60) return '$minutes min';
  final h = minutes / 60;
  final text = h == h.roundToDouble() ? h.toInt().toString() : h.toStringAsFixed(1);
  return h == 1 ? '1 hr' : '$text hrs';
}

enum MilestoneState {
  done('done'),
  active('active'),
  upcoming('upcoming');

  const MilestoneState(this.db);
  final String db;

  static MilestoneState fromDb(String? v) => MilestoneState.values
      .firstWhere((e) => e.db == v, orElse: () => MilestoneState.upcoming);
}

enum TaskTag {
  now('now', 'Now'),
  quiz('quiz', 'Quiz'),
  done('done', 'Done');

  const TaskTag(this.db, this.label);
  final String db;
  final String label;

  static TaskTag fromDb(String? v) =>
      TaskTag.values.firstWhere((e) => e.db == v, orElse: () => TaskTag.now);
}

/// The four review buttons on the flashcard screen. Maps to SM-2 quality
/// scores server-side in `apply_sr_grade`.
enum SrGrade {
  again('again', 'Again'),
  hard('hard', 'Hard'),
  good('good', 'Good'),
  easy('easy', 'Easy');

  const SrGrade(this.db, this.label);
  final String db;
  final String label;

  static SrGrade fromDb(String? v) =>
      SrGrade.values.firstWhere((e) => e.db == v, orElse: () => SrGrade.good);
}

enum MaterialType {
  syllabusPdf('syllabus_pdf', 'Syllabus PDF'),
  notes('notes', 'Notes'),
  videoLink('video_link', 'Video link');

  const MaterialType(this.db, this.label);
  final String db;
  final String label;

  static MaterialType fromDb(String? v) => MaterialType.values
      .firstWhere((e) => e.db == v, orElse: () => MaterialType.notes);
}

enum IngestStatus {
  uploaded('uploaded', 'Uploaded'),
  processing('processing', 'Processing…'),
  embedded('embedded', 'Ready'),
  failed('failed', 'Failed');

  const IngestStatus(this.db, this.label);
  final String db;
  final String label;

  bool get isTerminal => this == embedded || this == failed;

  static IngestStatus fromDb(String? v) => IngestStatus.values
      .firstWhere((e) => e.db == v, orElse: () => IngestStatus.uploaded);
}

enum ChatRole {
  user('user'),
  ai('ai');

  const ChatRole(this.db);
  final String db;

  static ChatRole fromDb(String? v) =>
      ChatRole.values.firstWhere((e) => e.db == v, orElse: () => ChatRole.ai);
}
