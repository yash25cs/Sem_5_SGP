// Ticking a task: a tap marks it done with Undo for a few seconds; after that
// a tap only says how to reopen it, and reopening is a long-press with a
// confirmation. And the chat's starter questions, written from the student's
// own files instead of a fixed list.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart' hide MaterialType;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:studytrail_flutter/data/repositories.dart';
import 'package:studytrail_flutter/models/models.dart';
import 'package:studytrail_flutter/screens/home_screen.dart';
import 'package:studytrail_flutter/state/chat_starters.dart';
import 'package:studytrail_flutter/state/stores.dart';
import 'package:studytrail_flutter/theme/app_theme.dart';

void main() {
  group('Home tasks', () {
    late _Tasks tasks;

    Future<void> pump(WidgetTester tester) async {
      tasks = _Tasks();
      tester.view.physicalSize = const Size(400 * 3, 1000 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<HomeStore>(
              create: (_) => HomeStore(
                    profiles: const _Profiles(),
                    goals: _Goals(),
                    tasks: tasks,
                    game: const _Game(),
                    roadmap: _Roadmap(),
                  )),
          ChangeNotifierProvider<WeakSpotsStore>(
              create: (_) => WeakSpotsStore(quizzes: _Quizzes())),
        ],
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: HomeScreen())),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('a tap marks it done, and Undo puts it back', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Revise normalisation'));
      await tester.pumpAndSettle();
      expect(tasks.calls, [('t1', true)]);
      expect(find.text('Done: Revise normalisation'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(tasks.calls, [('t1', true), ('t1', false)]);
    });

    testWidgets('Undo shows the moment the tick lands, before the save',
        (tester) async {
      await pump(tester);
      tasks.gate = Completer<void>();
      await tester.tap(find.text('Revise normalisation'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Undo'), findsOneWidget,
          reason: 'the save is still in flight');

      // Undo tapped mid-save waits for it, then goes through.
      await tester.tap(find.text('Undo'));
      await tester.pump();
      tasks.gate!.complete();
      tasks.gate = null;
      await tester.pumpAndSettle();
      expect(tasks.calls, [('t1', true), ('t1', false)]);
    });

    testWidgets('the Undo bar goes away on its own', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Revise normalisation'));
      await tester.pumpAndSettle();
      expect(find.text('Undo'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(find.text('Undo'), findsNothing);
    });

    testWidgets('a second tap does not untick; it explains the long-press',
        (tester) async {
      await pump(tester);
      await tester.tap(find.text('Revise normalisation'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Revise normalisation'));
      await tester.pumpAndSettle();
      expect(tasks.calls, [('t1', true)], reason: 'still done');
      expect(find.textContaining('Long-press it to mark it as not done'),
          findsOneWidget);
    });

    testWidgets('long-press asks, then reopens', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Revise normalisation'));
      await tester.pumpAndSettle();
      // Let the Undo window pass.
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Revise normalisation'));
      await tester.pumpAndSettle();
      expect(find.text('Mark as not done?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tasks.calls, [('t1', true)]);

      await tester.longPress(find.text('Revise normalisation'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark as not done'));
      await tester.pumpAndSettle();
      expect(tasks.calls, [('t1', true), ('t1', false)]);
    });

    testWidgets('long-pressing a pending task just ticks it, like a tap',
        (tester) async {
      await pump(tester);
      await tester.longPress(find.text('Revise normalisation'));
      await tester.pumpAndSettle();
      expect(find.text('Mark as not done?'), findsNothing);
      expect(tasks.calls, [('t1', true)]);
      expect(find.text('Undo'), findsOneWidget);
    });
  });

  group('Chat starters', () {
    test('about the student\'s files and units, weak spot first', () {
      final starters = buildChatStarters(
        random: Random(1),
        sources: const [
          StarterSource(title: '1700000000000_DBMS_notes.pdf', units: [
            'Unit 1: Normalisation',
            'Unit 2: Transactions',
            'Unit 2: Transactions',
            'Source',
          ]),
        ],
        weak: const [
          WeakTopic(
              materialId: 'm',
              materialTitle: 'DBMS',
              unitLabel: 'Unit 3: Indexing'),
        ],
      );
      expect(starters.first.kind, 'weak');
      expect(starters.first.label, 'Help with Indexing');
      expect(starters.first.prompt, contains('Unit 3: Indexing'));
      final prompts = starters.map((s) => s.prompt).join('\n');
      expect(prompts, contains('“DBMS notes”'),
          reason: 'the stored name is cleaned up');
      expect(prompts, isNot(contains('Source')));
      expect(starters.length, lessThanOrEqualTo(4));
      for (final s in starters) {
        expect(s.label.length, lessThanOrEqualTo(40), reason: s.label);
      }
    });

    test('video timestamps are not part of the topic', () {
      final starters = buildChatStarters(
        random: Random(2),
        sources: const [
          StarterSource(
              title: 'MIT 6.006 Lecture 1',
              units: ['9:40 · 1. Algorithms and Computation']),
        ],
      );
      final explain = starters.firstWhere((s) => s.kind == 'explain');
      expect(explain.label, 'Explain Algorithms and…');
      expect(explain.prompt, isNot(contains('9:40')));
    });

    test('files without units still get summaries; no files, nothing', () {
      final starters = buildChatStarters(sources: const [
        StarterSource(title: 'Physics.pdf'),
        StarterSource(title: 'Chemistry.pdf'),
      ]);
      expect(starters.map((s) => s.kind), everyElement('summary'));
      expect(starters, hasLength(2));
      expect(buildChatStarters(sources: const []), isEmpty);
    });

    test('the store loads them, and a failed read keeps the general ones',
        () async {
      final store = ChatStore(
          chat: _Chat(), goals: const _NoGoal(), quizzes: _Quizzes());
      await store.loadStarters();
      expect(store.starters, isNotEmpty);
      expect(store.starters.map((s) => s.prompt).join(),
          contains('Machine Learning'));

      final failing = ChatStore(
          chat: _Chat(fail: true), goals: const _NoGoal(), quizzes: _Quizzes());
      await failing.loadStarters();
      expect(failing.starters, isEmpty);
    });
  });
}

class _Tasks extends TaskRepository {
  final calls = <(String, bool)>[];
  final _done = <String, bool>{};

  /// When set, a save waits for it — a slow network.
  Completer<void>? gate;

  List<DailyTask> get _list => [
        for (final (id, title) in [
          ('t1', 'Revise normalisation'),
          ('t2', 'Practice SQL joins'),
        ])
          DailyTask(
            id: id,
            title: title,
            scheduledDate: DateTime.now(),
            done: _done[id] ?? false,
            tag: (_done[id] ?? false) ? TaskTag.done : TaskTag.now,
          ),
      ];

  @override
  Future<List<DailyTask>> getTodayTasks() async => _list;

  @override
  Future<DailyTask> setDone(DailyTask task, bool done) async {
    calls.add((task.id, done));
    final g = gate;
    if (g != null) await g.future;
    _done[task.id] = done;
    return _list.firstWhere((t) => t.id == task.id);
  }
}

class _Profiles extends ProfileRepository {
  const _Profiles();
  @override
  Future<Profile?> getMyProfile() async => null;
}

class _Goals extends GoalRepository {
  @override
  Future<List<Goal>> getGoals() async => [
        Goal(
            id: 'g',
            name: 'Semester 5',
            examDate: DateTime.now().add(const Duration(days: 30))),
      ];
  @override
  Future<List<Subject>> getSubjects(String goalId) async => const [];
}

class _NoGoal extends GoalRepository {
  const _NoGoal();
  @override
  Future<Goal?> getActiveGoal() async => null;
}

class _Game extends GamificationRepository {
  const _Game();
  @override
  Future<Streak> getStreak() async => const Streak(currentStreak: 3);
}

class _Roadmap extends RoadmapRepository {
  @override
  Future<RoadmapPace> getPace(String goalId) async =>
      const RoadmapPace(hasRoadmap: false);
}

class _Quizzes extends QuizRepository {
  @override
  Future<List<WeakTopic>> getWeakTopics({int limit = 5}) async => const [];
}

class _Chat extends ChatRepository {
  _Chat({this.fail = false});
  final bool fail;

  @override
  Future<List<StarterSource>> getStarterSources() async {
    if (fail) throw 'offline';
    return const [
      StarterSource(
          title: 'Machine Learning.pdf',
          units: ['Unit 1: Regression', 'Unit 2: Classification']),
    ];
  }
}
