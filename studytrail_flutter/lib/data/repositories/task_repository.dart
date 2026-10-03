import '../../models/models.dart';
import '../supabase_client.dart';

/// Reads and writes `daily_tasks` — the Home screen checklist.
class TaskRepository {
  const TaskRepository();

  /// Tasks for a given day, newest-first within the day. Embeds the subject
  /// name so the list can show it without a second round-trip.
  Future<List<DailyTask>> getTasksForDate(DateTime date) async {
    final day = _dateOnly(date);
    final rows = await db
        .from('daily_tasks')
        .select('*, subjects(name)')
        .eq('scheduled_date', day)
        .order('done', ascending: true)
        .order('tag', ascending: true);
    return rows.map(DailyTask.fromMap).toList();
  }

  Future<List<DailyTask>> getTodayTasks() => getTasksForDate(DateTime.now());

  /// Unfinished tasks from today on, soonest first — for the calendar export.
  Future<List<DailyTask>> getUpcomingTasks({int limit = 200}) async {
    final rows = await db
        .from('daily_tasks')
        .select('*, subjects(name)')
        .gte('scheduled_date', _dateOnly(DateTime.now()))
        .eq('done', false)
        .order('scheduled_date', ascending: true)
        .limit(limit);
    return rows.map(DailyTask.fromMap).toList();
  }

  Future<DailyTask> createTask({
    required String title,
    String? goalId,
    String? subjectId,
    String? milestoneTaskId,
    int? durationMin,
    TaskTag tag = TaskTag.now,
    DateTime? scheduledDate,
  }) async {
    final draft = DailyTask(
      id: '',
      title: title,
      subjectId: subjectId,
      milestoneTaskId: milestoneTaskId,
      durationMin: durationMin,
      tag: tag,
      scheduledDate: scheduledDate ?? DateTime.now(),
    );
    final row = await db
        .from('daily_tasks')
        .insert({
          ...draft.toInsertMap(),
          'user_id': requireUserId,
          'goal_id': ?goalId,
        })
        .select('*, subjects(name)')
        .single();
    return DailyTask.fromMap(row);
  }

  /// Schedules several roadmap tasks for one day in a single insert.
  ///
  /// Every row keeps its `milestone_task_id`, which is the whole point of this
  /// path: `complete_task` mirrors the tick back to `milestone_tasks` in the same
  /// transaction, so ticking on Home moves the roadmap with it.
  ///
  /// No `duration_min` — a milestone task carries no estimate, and inventing one
  /// would feed a made-up number into the study log's clamp.
  Future<List<DailyTask>> createTasksFromRoadmap({
    required String goalId,
    required List<MilestoneTask> tasks,
    DateTime? scheduledDate,
  }) async {
    if (tasks.isEmpty) return const [];
    final date = scheduledDate ?? DateTime.now();
    final rows = await db
        .from('daily_tasks')
        .insert([
          for (final task in tasks)
            {
              ...DailyTask(
                id: '',
                title: task.name,
                milestoneTaskId: task.id,
                scheduledDate: date,
              ).toInsertMap(),
              'user_id': requireUserId,
              'goal_id': goalId,
            },
        ])
        .select('*, subjects(name)');
    return rows.map(DailyTask.fromMap).toList();
  }

  /// The roadmap tasks that already have a `daily_tasks` row, on any date.
  ///
  /// `daily_tasks` has no unique constraint on `milestone_task_id`, so this is
  /// what stops a second tap from scheduling the same topic twice. Deliberately
  /// not limited to today: a task pulled in yesterday and left unticked is still
  /// on the student's list, not a fresh one to hand them again.
  Future<Set<String>> getScheduledMilestoneTaskIds(String goalId) async {
    final rows = await db
        .from('daily_tasks')
        .select('milestone_task_id')
        .eq('goal_id', goalId)
        .not('milestone_task_id', 'is', null);
    return {
      for (final row in rows)
        if (row['milestone_task_id'] case final String id) id,
    };
  }

  /// The `daily_tasks` row a roadmap task was scheduled as, if any.
  ///
  /// Used by the Roadmap screen so a tick there goes through `complete_task`
  /// rather than writing `milestone_tasks.done` directly — otherwise the same
  /// work would pay XP from Home and nothing from the roadmap.
  Future<String?> findDailyTaskForMilestoneTask(String milestoneTaskId) async {
    final row = await db
        .from('daily_tasks')
        .select('id')
        .eq('milestone_task_id', milestoneTaskId)
        .limit(1)
        .maybeSingle();
    return row?['id'] as String?;
  }

  /// Flips a task's done state through the `complete_task` RPC.
  ///
  /// The RPC also mirrors the linked roadmap checkbox and pays out XP — in one
  /// transaction, and only for a task's *first* completion, so re-ticking is
  /// worth nothing. Doing the mirror here as a second call could leave the two
  /// screens disagreeing if it failed.
  Future<DailyTask> setDone(DailyTask task, bool done) async {
    final saved = await _completeTask(task.id, done);
    // The RPC returns a bare row, so keep the subject name the list is already
    // showing — a done-toggle can't have changed it.
    return task.copyWith(done: saved.done, tag: saved.tag);
  }

  /// The same RPC for a caller that holds only the id — the Roadmap screen, when
  /// the task it ticked was also scheduled on Home.
  Future<DailyTask> setDoneById(String taskId, bool done) =>
      _completeTask(taskId, done);

  Future<DailyTask> _completeTask(String taskId, bool done) async {
    final row = await db.rpc('complete_task', params: {
      'p_task': taskId,
      'p_done': done,
    });
    return DailyTask.fromMap(
      row is List
          ? row.first as Map<String, dynamic>
          : row as Map<String, dynamic>,
    );
  }

  Future<void> deleteTask(String taskId) =>
      db.from('daily_tasks').delete().eq('id', taskId);

  static String _dateOnly(DateTime d) =>
      DateTime(d.year, d.month, d.day).toIso8601String().split('T').first;
}
