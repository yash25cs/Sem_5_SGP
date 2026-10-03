// Catch-up planner: the pace model and HomeStore.catchUp, with Supabase faked
// at the repository seam.

import 'package:flutter_test/flutter_test.dart';

import 'package:studytrail_flutter/data/repositories.dart';
import 'package:studytrail_flutter/models/models.dart';
import 'package:studytrail_flutter/state/stores.dart';

void main() {
  group('RoadmapPace', () {
    test('reads the RPC and knows when to offer a catch-up', () {
      final behind = RoadmapPace.fromMap({
        'has_roadmap': true,
        'total': 20,
        'done': 0,
        'expected': 6,
        'behind': 6,
        'days_left': 28,
        'per_day': 1,
        'overdue': 0,
      });
      expect(behind.needsCatchUp, isTrue);
      expect(behind.perDay, 1);

      expect(
          RoadmapPace.fromMap({'has_roadmap': true, 'behind': 0, 'overdue': 0})
              .needsCatchUp,
          isFalse);
      // Missed days alone are reason enough, even when the line says on track.
      expect(
          RoadmapPace.fromMap({'has_roadmap': true, 'behind': 0, 'overdue': 2})
              .needsCatchUp,
          isTrue);
      expect(RoadmapPace.fromMap({'has_roadmap': false, 'overdue': 3})
          .needsCatchUp, isFalse);
    });
  });

  group('HomeStore.catchUp', () {
    test('plans, reloads today, and refreshes the pace', () async {
      final roadmap = _PaceRoadmap();
      final tasks = _TodayTasks();
      final store = HomeStore(
        profiles: const _Profiles(),
        goals: const _Goals(),
        tasks: tasks,
        game: const _Game(),
        roadmap: roadmap,
      );
      addTearDown(store.dispose);

      await store.load();
      expect(store.pace!.needsCatchUp, isTrue);

      tasks.today = [
        DailyTask(id: 't1', title: 'Moved', scheduledDate: DateTime(2026, 10, 1)),
      ];
      roadmap.caughtUp = true;
      final result = await store.catchUp();

      expect(result!.moved, 1);
      expect(roadmap.planned, ['goal-1']);
      expect(store.tasks.single.title, 'Moved');
      expect(store.pace!.needsCatchUp, isFalse);
    });

    test('a failure keeps the banner and says why', () async {
      final store = HomeStore(
        profiles: const _Profiles(),
        goals: const _Goals(),
        tasks: _TodayTasks(),
        game: const _Game(),
        roadmap: _PaceRoadmap(failing: true),
      );
      addTearDown(store.dispose);
      await store.load();

      expect(await store.catchUp(), isNull);
      expect(store.error, isNotNull);
      expect(store.pace!.needsCatchUp, isTrue);
    });
  });
}

class _Profiles extends ProfileRepository {
  const _Profiles();
  @override
  Future<Profile?> getMyProfile() async => null;
}

class _Goals extends GoalRepository {
  const _Goals();
  @override
  Future<List<Goal>> getGoals() async =>
      const [Goal(id: 'goal-1', name: 'DBMS end-sem')];
  @override
  Future<List<Subject>> getSubjects(String goalId) async => const [];
}

class _Game extends GamificationRepository {
  const _Game();
  @override
  Future<Streak> getStreak() async => const Streak();
}

class _TodayTasks extends TaskRepository {
  List<DailyTask> today = const [];
  @override
  Future<List<DailyTask>> getTodayTasks() async => today;
}

class _PaceRoadmap extends RoadmapRepository {
  _PaceRoadmap({this.failing = false});
  final bool failing;
  bool caughtUp = false;
  final planned = <String>[];

  @override
  Future<RoadmapPace> getPace(String goalId) async => RoadmapPace(
        hasRoadmap: true,
        total: 20,
        behind: caughtUp ? 0 : 6,
        overdue: caughtUp ? 0 : 1,
        perDay: 1,
        daysLeft: 28,
      );

  @override
  Future<CatchUpResult> planCatchUp(String goalId) async {
    if (failing) throw Exception('plan_catch_up never answered');
    planned.add(goalId);
    return const CatchUpResult(perDay: 1, moved: 1, scheduled: 6, daysLeft: 28);
  }
}
