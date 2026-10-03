// Per-subject exam dates: day counting and which exam is "next".

import 'package:flutter_test/flutter_test.dart';

import 'package:studytrail_flutter/data/repositories.dart';
import 'package:studytrail_flutter/models/models.dart';
import 'package:studytrail_flutter/state/stores.dart';

void main() {
  test('days until an exam count whole calendar days', () {
    final now = DateTime(2026, 10, 1, 23, 50);
    final s = Subject(id: 's', name: 'DBMS', examDate: DateTime(2026, 10, 15));
    expect(s.daysUntilExam(now), 14);
    expect(const Subject(id: 's', name: 'OS').daysUntilExam(now), isNull);
    expect(
        Subject(id: 's', name: 'CN', examDate: DateTime(2026, 9, 30))
            .daysUntilExam(now),
        -1);
  });

  test('Subject reads exam_date from its row', () {
    final s = Subject.fromMap({'id': 's', 'name': 'DBMS', 'exam_date': '2026-10-15'});
    expect(s.examDate, DateTime(2026, 10, 15));
  });

  test('next exam is the soonest one still ahead, past ones skipped', () async {
    final today = DateTime.now();
    DateTime inDays(int d) => DateTime(today.year, today.month, today.day + d);
    final store = HomeStore(
      profiles: const _Profiles(),
      goals: _Goals([
        Subject(id: 'a', name: 'OS', examDate: inDays(20)),
        Subject(id: 'b', name: 'CN', examDate: inDays(-2)),
        Subject(id: 'c', name: 'DBMS', examDate: inDays(6)),
        const Subject(id: 'd', name: 'Maths'),
      ]),
      tasks: _Tasks(),
      game: const _Game(),
      roadmap: _Roadmap(),
    );
    addTearDown(store.dispose);
    await store.load();
    expect(store.nextExam?.name, 'DBMS');
  });
}

class _Profiles extends ProfileRepository {
  const _Profiles();
  @override
  Future<Profile?> getMyProfile() async => null;
}

class _Goals extends GoalRepository {
  _Goals(this.subjects);
  final List<Subject> subjects;
  @override
  Future<List<Goal>> getGoals() async => const [Goal(id: 'g', name: 'Sem 5')];
  @override
  Future<List<Subject>> getSubjects(String goalId) async => subjects;
}

class _Tasks extends TaskRepository {
  @override
  Future<List<DailyTask>> getTodayTasks() async => const [];
}

class _Game extends GamificationRepository {
  const _Game();
  @override
  Future<Streak> getStreak() async => const Streak();
}

class _Roadmap extends RoadmapRepository {
  @override
  Future<RoadmapPace> getPace(String goalId) async => const RoadmapPace();
}
