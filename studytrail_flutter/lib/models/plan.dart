import 'enums.dart';

/// A row of `subjects` — one paper/topic inside a goal.
class Subject {
  const Subject({
    required this.id,
    required this.name,
    this.goalId,
    this.iconKey,
    this.colorKey,
    this.isFocus = true,
    this.progress = 0,
    this.accuracy = 0,
    this.examDate,
  });

  final String id;
  final String name;
  final String? goalId;
  final String? iconKey;
  final String? colorKey;
  final bool isFocus;
  final double progress;
  final double accuracy;

  /// This subject's own paper, when the semester has several exam days.
  final DateTime? examDate;

  /// Whole days from today (the phone's date) to [examDate]; null if undated.
  int? daysUntilExam([DateTime? now]) {
    final exam = examDate;
    if (exam == null) return null;
    final n = now ?? DateTime.now();
    return DateTime(exam.year, exam.month, exam.day)
        .difference(DateTime(n.year, n.month, n.day))
        .inDays;
  }

  factory Subject.fromMap(Map<String, dynamic> m) => Subject(
        id: m['id'] as String,
        name: (m['name'] as String?) ?? '',
        goalId: m['goal_id'] as String?,
        iconKey: m['icon_key'] as String?,
        colorKey: m['color_key'] as String?,
        isFocus: (m['is_focus'] as bool?) ?? true,
        progress: (m['progress'] as num?)?.toDouble() ?? 0,
        accuracy: (m['accuracy'] as num?)?.toDouble() ?? 0,
        examDate: m['exam_date'] == null
            ? null
            : DateTime.parse(m['exam_date'] as String),
      );

  Map<String, dynamic> toInsertMap() => {
        'name': name,
        if (goalId != null) 'goal_id': goalId,
        'icon_key': iconKey,
        'color_key': colorKey,
        'is_focus': isFocus,
      };
}

/// A row of `milestones` plus its nested `milestone_tasks`.
class Milestone {
  const Milestone({
    required this.id,
    required this.title,
    this.weekLabel,
    this.state = MilestoneState.upcoming,
    this.orderIndex = 0,
    this.colorKey,
    this.tasks = const [],
  });

  final String id;
  final String title;
  final String? weekLabel;
  final MilestoneState state;
  final int orderIndex;
  final String? colorKey;
  final List<MilestoneTask> tasks;

  int get doneCount => tasks.where((t) => t.done).length;

  double get progress => tasks.isEmpty ? 0 : doneCount / tasks.length;

  /// Reads the nested `milestone_tasks` array when the query selected it.
  factory Milestone.fromMap(Map<String, dynamic> m) {
    final raw = m['milestone_tasks'];
    final tasks = raw is List
        ? raw
            .cast<Map<String, dynamic>>()
            .map(MilestoneTask.fromMap)
            .toList()
        : const <MilestoneTask>[];
    tasks.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

    return Milestone(
      id: m['id'] as String,
      title: (m['title'] as String?) ?? '',
      weekLabel: m['week_label'] as String?,
      state: MilestoneState.fromDb(m['state'] as String?),
      orderIndex: (m['order_index'] as num?)?.toInt() ?? 0,
      colorKey: m['color_key'] as String?,
      tasks: tasks,
    );
  }

  Milestone copyWith({MilestoneState? state, List<MilestoneTask>? tasks}) =>
      Milestone(
        id: id,
        title: title,
        weekLabel: weekLabel,
        state: state ?? this.state,
        orderIndex: orderIndex,
        colorKey: colorKey,
        tasks: tasks ?? this.tasks,
      );
}

/// A row of `milestone_tasks` — a checkbox under a milestone.
class MilestoneTask {
  const MilestoneTask({
    required this.id,
    required this.name,
    this.done = false,
    this.orderIndex = 0,
  });

  final String id;
  final String name;
  final bool done;
  final int orderIndex;

  factory MilestoneTask.fromMap(Map<String, dynamic> m) => MilestoneTask(
        id: m['id'] as String,
        name: (m['name'] as String?) ?? '',
        done: (m['done'] as bool?) ?? false,
        orderIndex: (m['order_index'] as num?)?.toInt() ?? 0,
      );

  MilestoneTask copyWith({bool? done}) => MilestoneTask(
        id: id,
        name: name,
        done: done ?? this.done,
        orderIndex: orderIndex,
      );
}

/// A row of `daily_tasks` — today's checklist on the Home screen.
class DailyTask {
  const DailyTask({
    required this.id,
    required this.title,
    this.subjectId,
    this.subjectName,
    this.milestoneTaskId,
    this.durationMin,
    this.tag = TaskTag.now,
    required this.scheduledDate,
    this.done = false,
  });

  final String id;
  final String title;
  final String? subjectId;

  /// Joined from `subjects` when the query embeds it; not a column.
  final String? subjectName;
  final String? milestoneTaskId;
  final int? durationMin;
  final TaskTag tag;
  final DateTime scheduledDate;
  final bool done;

  String get durationLabel =>
      durationMin == null ? '' : '$durationMin min';

  factory DailyTask.fromMap(Map<String, dynamic> m) {
    final subject = m['subjects'];
    return DailyTask(
      id: m['id'] as String,
      title: (m['title'] as String?) ?? '',
      subjectId: m['subject_id'] as String?,
      subjectName:
          subject is Map<String, dynamic> ? subject['name'] as String? : null,
      milestoneTaskId: m['milestone_task_id'] as String?,
      durationMin: (m['duration_min'] as num?)?.toInt(),
      tag: TaskTag.fromDb(m['tag'] as String?),
      scheduledDate: DateTime.parse(m['scheduled_date'] as String),
      done: (m['done'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toInsertMap() => {
        'title': title,
        if (subjectId != null) 'subject_id': subjectId,
        if (milestoneTaskId != null) 'milestone_task_id': milestoneTaskId,
        if (durationMin != null) 'duration_min': durationMin,
        'tag': tag.db,
        'scheduled_date': scheduledDate.toIso8601String().split('T').first,
      };

  DailyTask copyWith({bool? done, TaskTag? tag}) => DailyTask(
        id: id,
        title: title,
        subjectId: subjectId,
        subjectName: subjectName,
        milestoneTaskId: milestoneTaskId,
        durationMin: durationMin,
        tag: tag ?? this.tag,
        scheduledDate: scheduledDate,
        done: done ?? this.done,
      );
}
