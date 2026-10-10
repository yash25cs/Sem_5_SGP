import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/models.dart';
import '../supabase_client.dart';

/// Reads and writes `goals` + `subjects`. RLS scopes every query to the
/// signed-in user, so no `user_id` filter is needed on selects.
class GoalRepository {
  const GoalRepository();

  /// The goal the app is currently working against — newest active one.
  Future<Goal?> getActiveGoal() async {
    final rows = await db
        .from('goals')
        .select()
        .eq('is_active', true)
        .order('created_at', ascending: false)
        .limit(1);
    if (rows.isEmpty) return null;
    return Goal.fromMap(rows.first);
  }

  /// Cheap existence check for the onboarding gate.
  Future<bool> hasAnyGoal() async {
    final rows = await db.from('goals').select('id').limit(1);
    return rows.isNotEmpty;
  }

  Future<List<Goal>> getGoals() async {
    final rows =
        await db.from('goals').select().order('created_at', ascending: false);
    return rows.map(Goal.fromMap).toList();
  }

  /// Makes [goalId] the goal the app works against.
  ///
  /// Two statements rather than one: PostgREST can't express
  /// `is_active = (id = $1)` in a single update, and adding an RPC for it would
  /// block this on applying another migration. The retire-others call goes
  /// first, so the worst outcome of a drop between them is *no* active goal —
  /// which the UI shows as "no goal" and the student can fix with another tap —
  /// rather than two, which would silently pick whichever is newer.
  Future<void> setActiveGoal(String goalId) async {
    await db
        .from('goals')
        .update({'is_active': false})
        .eq('is_active', true)
        .neq('id', goalId);
    await db.from('goals').update({'is_active': true}).eq('id', goalId);
  }

  /// Creates a goal and its subjects, and retires the previously active one.
  ///
  /// All three writes happen inside the `create_goal` RPC, so they succeed or
  /// fail together. Doing them here as three calls left a real failure mode: a
  /// drop after the first one deactivated the old goal but never created the
  /// new one, and the student was left with no active goal and no way to notice
  /// (docs/REVIEW.md P1). `user_id` comes from the JWT inside the function, so it
  /// isn't sent.
  ///
  /// [subjectExamDates] runs parallel to [subjectNames]: entry `i` is the date
  /// of subject `i`'s paper, and a missing or null entry leaves it undated.
  ///
  /// Falls back to the three separate writes when the project doesn't have the
  /// function yet — see [_createGoalWithoutRpc].
  Future<Goal> createGoal({
    required String name,
    DateTime? examDate,
    Pace pace = Pace.steady,
    List<String> subjectNames = const [],
    List<DateTime?> subjectExamDates = const [],
    int? dailyMinutes,
  }) async {
    final goal = await _createGoal(
      name: name,
      examDate: examDate,
      pace: dailyMinutes == null ? pace : Pace.nearest(dailyMinutes),
      subjectNames: subjectNames,
      subjectExamDates: subjectExamDates,
    );
    if (dailyMinutes == null) return goal;
    // create_goal doesn't take it; set straight after, before the roadmap is
    // written from the goal.
    return updateGoal(goalId: goal.id, dailyMinutes: dailyMinutes);
  }

  Future<Goal> _createGoal({
    required String name,
    DateTime? examDate,
    Pace pace = Pace.steady,
    List<String> subjectNames = const [],
    List<DateTime?> subjectExamDates = const [],
  }) async {
    final goalName = name.trim();
    // Built together so dropping a blank name can't shift the dates over.
    final subjects = <String>[];
    final dates = <String?>[];
    for (final (i, n) in subjectNames.indexed) {
      if (n.trim().isEmpty) continue;
      subjects.add(n.trim());
      dates.add(_day(i < subjectExamDates.length ? subjectExamDates[i] : null));
    }

    try {
      final row = await db.rpc('create_goal', params: {
        'p_name': goalName,
        'p_exam_date': _day(examDate),
        'p_pace': pace.db,
        'p_subjects': subjects,
        // 0025. Before it, naming this argument finds no function (PGRST202)
        // and the fallback below writes the same rows.
        'p_subject_dates': dates,
      });
      return Goal.fromMap(
        row is List
            ? row.first as Map<String, dynamic>
            : row as Map<String, dynamic>,
      );
    } on PostgrestException catch (error) {
      // PGRST202 = "Could not find the function public.create_goal … in the
      // schema cache", i.e. migration 0009 or 0025 hasn't been applied.
      // Anything else is a real failure and stays a failure.
      if (error.code != 'PGRST202') rethrow;
      return _createGoalWithoutRpc(
        name: goalName,
        examDate: examDate,
        pace: pace,
        subjectNames: subjects,
        subjectExamDates: dates,
      );
    }
  }

  /// A `date` column takes the day only, not a full timestamp.
  static String? _day(DateTime? date) =>
      date?.toIso8601String().split('T').first;

  /// Creates the goal with plain inserts, for a project still running a schema
  /// from before `create_goal` existed.
  ///
  /// Not atomic — that's the whole reason 0009 exists — so the statement order
  /// is chosen for the least damaging interruption: the goal is inserted first
  /// and `goals.is_active` defaults to true, so a drop before the retire step
  /// leaves *two* active goals, and [getActiveGoal] takes the newest, which is
  /// the one just created. Retiring first would leave no active goal at all.
  Future<Goal> _createGoalWithoutRpc({
    required String name,
    required DateTime? examDate,
    required Pace pace,
    required List<String> subjectNames,
    required List<String?> subjectExamDates,
  }) async {
    final userId = requireUserId;

    final row = await db
        .from('goals')
        .insert({
          'user_id': userId,
          'name': name,
          'exam_date': _day(examDate),
          'pace': pace.db,
        })
        .select()
        .single();
    final goal = Goal.fromMap(row);

    await db
        .from('goals')
        .update({'is_active': false})
        .eq('user_id', userId)
        .eq('is_active', true)
        .neq('id', goal.id);

    // Case-insensitive dedupe, as the RPC does: there is no unique index on
    // (goal_id, name) to lean on, so "DBMS" and "dbms" would both land.
    final seen = <String>{};
    final subjectRows = [
      for (final (i, n) in subjectNames.indexed)
        if (seen.add(n.toLowerCase()))
          {
            'user_id': userId,
            'goal_id': goal.id,
            'name': n,
            // 0018's column; a project without it has no per-subject dates.
            if (subjectExamDates[i] != null) 'exam_date': subjectExamDates[i],
          },
    ];
    if (subjectRows.isNotEmpty) {
      await db.from('subjects').insert(subjectRows);
    }

    return goal;
  }

  /// Updates the fields that were passed and returns the saved row, so callers
  /// don't have to re-read to refresh their view.
  Future<Goal> updateGoal({
    required String goalId,
    String? name,
    DateTime? examDate,
    Pace? pace,
    int? dailyMinutes,
  }) async {
    final examDay = examDate?.toIso8601String().split('T').first;
    final row = await db
        .from('goals')
        .update({
          'name': ?name,
          'exam_date': ?examDay,
          // A custom time a day keeps the nearest preset beside it; picking a
          // preset clears the custom time.
          if (dailyMinutes != null) ...{
            'daily_minutes': dailyMinutes,
            'pace': Pace.nearest(dailyMinutes).db,
          } else if (pace != null) ...{
            'pace': pace.db,
            'daily_minutes': null,
          },
        })
        .eq('id', goalId)
        .select()
        .single();
    return Goal.fromMap(row);
  }

  Future<void> deleteGoal(String goalId) =>
      db.from('goals').delete().eq('id', goalId);

  /// Sets (or with null clears) one subject's exam date. A date later than
  /// the goal's own pushes the goal's date out to it (0018's trigger).
  Future<void> setSubjectExamDate(String subjectId, DateTime? date) async {
    await db.from('subjects').update({
      'exam_date': date == null
          ? null
          : DateTime(date.year, date.month, date.day)
              .toIso8601String()
              .split('T')
              .first,
    }).eq('id', subjectId);
  }

  Future<List<Subject>> getSubjects(String goalId) async {
    final rows = await db
        .from('subjects')
        .select()
        .eq('goal_id', goalId)
        .order('name', ascending: true);
    return rows.map(Subject.fromMap).toList();
  }
}
