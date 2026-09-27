import '../../models/models.dart';
import '../supabase_client.dart';
import 'task_repository.dart';

/// What a roadmap checkbox write ended up doing.
///
/// [touchedDailyTask] is true when the task was also on Home's checklist, so the
/// tick went through `complete_task` and Home's copy is now stale.
typedef ToggleOutcome = ({MilestoneState state, bool touchedDailyTask});

/// Reads and writes `milestones` + `milestone_tasks` — the Roadmap screen.
class RoadmapRepository {
  const RoadmapRepository({TaskRepository tasks = const TaskRepository()})
      : _tasks = tasks;

  final TaskRepository _tasks;

  /// Milestones for a goal with their tasks nested, in display order.
  Future<List<Milestone>> getMilestones(String goalId) async {
    final rows = await db
        .from('milestones')
        .select('*, milestone_tasks(*)')
        .eq('goal_id', goalId)
        .order('order_index', ascending: true);
    return rows.map(Milestone.fromMap).toList();
  }

  /// Flips a roadmap checkbox and re-derives the parent milestone's state.
  ///
  /// When the task was also scheduled on Home, the tick goes through
  /// `complete_task` instead of a direct write: that RPC owns the XP, the streak,
  /// and `daily_tasks.done`. Writing `milestone_tasks.done` on its own here would
  /// leave Home still asking for work the student had just finished, and would
  /// quietly cost them the XP — `complete_task` is idempotent, so once
  /// `daily_tasks.done` matched, a later tick from Home would pay nothing.
  Future<ToggleOutcome> toggleTask(
    String milestoneId,
    String taskId,
    bool done,
  ) async {
    final dailyTaskId = await _tasks.findDailyTaskForMilestoneTask(taskId);
    if (dailyTaskId == null) {
      await db.from('milestone_tasks').update({'done': done}).eq('id', taskId);
    } else {
      // Mirrors `milestone_tasks.done` itself, in the same transaction.
      await _tasks.setDoneById(dailyTaskId, done);
    }
    return (
      state: await _deriveMilestoneState(milestoneId),
      touchedDailyTask: dailyTaskId != null,
    );
  }

  /// All done → done, some done → active, none → upcoming.
  Future<MilestoneState> _deriveMilestoneState(String milestoneId) async {
    final siblings = await db
        .from('milestone_tasks')
        .select('done')
        .eq('milestone_id', milestoneId);

    final total = siblings.length;
    final doneCount =
        siblings.where((r) => (r['done'] as bool?) ?? false).length;

    final state = switch (doneCount) {
      0 => MilestoneState.upcoming,
      _ when doneCount == total => MilestoneState.done,
      _ => MilestoneState.active,
    };

    await db
        .from('milestones')
        .update({'state': state.db}).eq('id', milestoneId);
    return state;
  }

  /// Re-derives the state of the milestone a task belongs to.
  ///
  /// Home's checklist ticks through `complete_task`, which flips
  /// `milestone_tasks.done` but knows nothing about the parent's `state` column —
  /// that one is derived, and this is what keeps the timeline's dots honest after
  /// a tick from the other screen.
  Future<void> resyncMilestoneForTask(String milestoneTaskId) async {
    final row = await db
        .from('milestone_tasks')
        .select('milestone_id')
        .eq('id', milestoneTaskId)
        .maybeSingle();
    final milestoneId = row?['milestone_id'] as String?;
    if (milestoneId == null) return;
    await _deriveMilestoneState(milestoneId);
  }

  /// Overall completion across a goal's roadmap tasks, counted and persisted by
  /// the `recompute_goal_progress` RPC.
  ///
  /// Deliberately not computed here: `goals.overall_percent` is the input to the
  /// goal_crusher badge, so it isn't the client's to assert. 0008_rewards.sql
  /// revokes UPDATE on that column.
  Future<double> recomputeGoalProgress(String goalId) async {
    final result = await db.rpc(
      'recompute_goal_progress',
      params: {'p_goal': goalId},
    );
    return (result as num?)?.toDouble() ?? 0;
  }

  Future<void> deleteMilestones(String goalId) =>
      db.from('milestones').delete().eq('goal_id', goalId);

  /// Asks the `generate-roadmap` Edge Function to write a weekly plan for this
  /// goal. Returns how many milestones it saved.
  ///
  /// There is no client-side fallback, and can't be: `0008_rewards.sql` revokes
  /// `insert` on `milestones` and `milestone_tasks` from `authenticated`, so the
  /// function's service-role write is the only route a roadmap exists through.
  ///
  /// Replaces rather than appends — the function clears the goal's existing
  /// milestones first, so [deleteMilestones] isn't needed around this call.
  Future<int> generateRoadmap(String goalId) async {
    final res = await db.functions.invoke(
      'generate-roadmap',
      body: {'goalId': goalId},
    );
    final data = res.data;
    if (data is Map && data['milestones'] is int) {
      return data['milestones'] as int;
    }
    return 0;
  }
}
