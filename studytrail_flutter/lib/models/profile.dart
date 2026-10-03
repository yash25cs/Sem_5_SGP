import 'enums.dart';

/// The language AI explanations come back in (`profiles.answer_language`).
/// Questions stay in English, like the exams.
enum AnswerLanguage {
  english('en', 'English'),
  hindi('hi', 'हिन्दी (Hindi)'),
  gujarati('gu', 'ગુજરાતી (Gujarati)');

  const AnswerLanguage(this.code, this.label);
  final String code;
  final String label;

  static AnswerLanguage fromCode(String? code) => AnswerLanguage.values
      .firstWhere((l) => l.code == code, orElse: () => AnswerLanguage.english);
}

/// A row of `profiles`. PK is the Supabase auth user id.
class Profile {
  const Profile({
    required this.id,
    this.fullName = '',
    this.enrollmentId,
    this.branch,
    this.college,
    this.email,
    this.avatarInitial,
    this.level = 1,
    this.xp = 0,
    this.xpToNext = 500,
    this.classId,
    this.answerLanguage = AnswerLanguage.english,
  });

  final String id;
  final String fullName;
  final String? enrollmentId;
  final String? branch;
  final String? college;
  final String? email;
  final String? avatarInitial;
  final int level;
  final int xp;
  final int xpToNext;
  final String? classId;
  final AnswerLanguage answerLanguage;

  /// First letter for the avatar circle, falling back through name → email.
  String get initial {
    final a = avatarInitial?.trim();
    if (a != null && a.isNotEmpty) return a[0].toUpperCase();
    final n = fullName.trim();
    if (n.isNotEmpty) return n[0].toUpperCase();
    final e = email?.trim() ?? '';
    return e.isNotEmpty ? e[0].toUpperCase() : '?';
  }

  /// 0–1 progress toward the next level, for the XP bar.
  double get levelProgress =>
      xpToNext <= 0 ? 0 : (xp % xpToNext) / xpToNext;

  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
        id: m['id'] as String,
        fullName: (m['full_name'] as String?) ?? '',
        enrollmentId: m['enrollment_id'] as String?,
        branch: m['branch'] as String?,
        college: m['college'] as String?,
        email: m['email'] as String?,
        avatarInitial: m['avatar_initial'] as String?,
        level: (m['level'] as num?)?.toInt() ?? 1,
        xp: (m['xp'] as num?)?.toInt() ?? 0,
        xpToNext: (m['xp_to_next'] as num?)?.toInt() ?? 500,
        classId: m['class_id'] as String?,
        answerLanguage: AnswerLanguage.fromCode(m['answer_language'] as String?),
      );

  /// Only the user-editable fields; ids and XP are server-owned.
  Map<String, dynamic> toUpdateMap() => {
        'full_name': fullName,
        'enrollment_id': enrollmentId,
        'branch': branch,
        'college': college,
      };

  Profile copyWith({
    String? fullName,
    String? enrollmentId,
    String? branch,
    String? college,
    int? level,
    int? xp,
    int? xpToNext,
    String? classId,
  }) =>
      Profile(
        id: id,
        fullName: fullName ?? this.fullName,
        enrollmentId: enrollmentId ?? this.enrollmentId,
        branch: branch ?? this.branch,
        college: college ?? this.college,
        email: email,
        avatarInitial: avatarInitial,
        level: level ?? this.level,
        xp: xp ?? this.xp,
        xpToNext: xpToNext ?? this.xpToNext,
        classId: classId ?? this.classId,
        answerLanguage: answerLanguage,
      );
}

/// A row of `goals` — the exam the user is preparing for.
class Goal {
  const Goal({
    required this.id,
    required this.name,
    this.examDate,
    this.pace = Pace.steady,
    this.roadmapDays,
    this.currentDay = 1,
    this.overallPercent = 0,
    this.isActive = true,
    this.roadmapStartedOn,
  });

  final String id;
  final String name;
  final DateTime? examDate;
  final Pace pace;
  final int? roadmapDays;
  final int currentDay;
  final double overallPercent;
  final bool isActive;

  /// When the generated roadmap's week 1 began (`0015_catch_up.sql`).
  final DateTime? roadmapStartedOn;

  /// Whole days until the exam, floored at 0. Null when no date is set.
  int? get daysLeft {
    if (examDate == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final exam = DateTime(examDate!.year, examDate!.month, examDate!.day);
    final d = exam.difference(today).inDays;
    return d < 0 ? 0 : d;
  }

  factory Goal.fromMap(Map<String, dynamic> m) => Goal(
        id: m['id'] as String,
        name: (m['name'] as String?) ?? '',
        examDate: m['exam_date'] == null
            ? null
            : DateTime.parse(m['exam_date'] as String),
        pace: Pace.fromDb(m['pace'] as String?),
        roadmapDays: (m['roadmap_days'] as num?)?.toInt(),
        currentDay: (m['current_day'] as num?)?.toInt() ?? 1,
        overallPercent: (m['overall_percent'] as num?)?.toDouble() ?? 0,
        roadmapStartedOn: m['roadmap_started_on'] == null
            ? null
            : DateTime.parse(m['roadmap_started_on'] as String),
        isActive: (m['is_active'] as bool?) ?? true,
      );

  /// `user_id` is filled in by the repository from the live session.
  Map<String, dynamic> toInsertMap() => {
        'name': name,
        // date column → send date-only, not a full timestamp.
        'exam_date': examDate?.toIso8601String().split('T').first,
        'pace': pace.db,
        if (roadmapDays != null) 'roadmap_days': roadmapDays,
      };
}
