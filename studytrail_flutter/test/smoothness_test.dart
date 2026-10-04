// The launch and loading work from Day 25: tabs built when first opened, Home
// fetched during the splash, Rewards' reads run together, Edge Functions
// pinned next to the database, and the study-room clock ticking without
// rebuilding the room. Supabase is faked at the repository seam.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:studytrail_flutter/data/repositories.dart';
import 'package:studytrail_flutter/data/timeout_http_client.dart';
import 'package:studytrail_flutter/models/models.dart';
import 'package:studytrail_flutter/state/stores.dart';
import 'package:studytrail_flutter/widgets/lazy_indexed_stack.dart';

void main() {
  testWidgets('Plus Jakarta Sans comes from the app, not the network',
      (tester) async {
    // With downloading off, a weight that isn't bundled — or is bundled under
    // a name google_fonts doesn't match — fails here instead of quietly
    // falling back to a download on a student's phone.
    GoogleFonts.config.allowRuntimeFetching = false;
    addTearDown(() => GoogleFonts.config.allowRuntimeFetching = true);
    await tester.runAsync(() => GoogleFonts.pendingFonts([
          for (final weight in [
            FontWeight.w400,
            FontWeight.w500,
            FontWeight.w600,
            FontWeight.w700,
            FontWeight.w800,
            // Not shipped by the family; must resolve to the nearest, 800.
            FontWeight.w900,
          ])
            GoogleFonts.plusJakartaSans(fontWeight: weight),
        ]));
  });

  testWidgets('a tab is built when first shown, and kept after',
      (tester) async {
    final built = <int>[];
    Widget tabs(int index) => Directionality(
          textDirection: TextDirection.ltr,
          child: LazyIndexedStack(index: index, children: [
            for (var i = 0; i < 3; i++) _Tab(i, onBuilt: built.add),
          ]),
        );

    await tester.pumpWidget(tabs(0));
    expect(built, [0], reason: 'only the open tab loads at launch');

    await tester.pumpWidget(tabs(2));
    expect(built, [0, 2]);

    await tester.pumpWidget(tabs(0));
    await tester.pumpWidget(tabs(2));
    expect(built, [0, 2], reason: 'a visited tab keeps its state');
  });

  group('Home during the splash', () {
    test('a prefetch hands over once, so Home does not load twice', () async {
      final goals = _Goals();
      final store = _home(goals);
      addTearDown(store.dispose);

      await store.prefetch();
      expect(goals.reads, 1);
      expect(store.takePrefetch(), isTrue);
      expect(store.takePrefetch(), isFalse,
          reason: 'later loads — after an edit — must still happen');
    });

    test('subjects and pace are read together, not one after the other',
        () async {
      final overlap = _Overlap();
      final store =
          _home(_Goals(overlap: overlap), roadmap: _Roadmap(overlap: overlap));
      addTearDown(store.dispose);

      await store.load();

      expect(overlap.mostAtOnce, 2);
      expect(store.subjects, hasLength(1));
    });
  });

  group('Rewards, Leaderboard and Achievements', () {
    test('read in two rounds, badges after the evaluation', () async {
      final game = _Game();
      final store = GamificationStore(game: game, profiles: const _Profiles());
      addTearDown(store.dispose);

      await store.load();

      // Everything but the badge list starts alongside the evaluation.
      expect(game.mostAtOnce, greaterThanOrEqualTo(4));
      expect(game.order.indexOf('badges'),
          greaterThan(game.order.indexOf('evaluated')));
      expect(store.badges.single.name, 'Unlocked just now');
      expect(store.leaderboard, hasLength(1));
      expect(store.streak.currentStreak, 4);
    });

    test('one failed read falls back without blanking the rest', () async {
      final store = GamificationStore(
          game: _Game(failLeaderboard: true), profiles: const _Profiles());
      addTearDown(store.dispose);

      await store.load();

      expect(store.error, isNull);
      expect(store.leaderboard, isEmpty);
      expect(store.streak.currentStreak, 4);
      expect(store.badges, isNotEmpty);
    });
  });

  group('Edge Function region', () {
    Future<Map<String, String>> headersFor(String path,
        {String region = 'ap-southeast-2'}) async {
      late Map<String, String> seen;
      final client = TimeoutHttpClient(
        functionsRegion: region,
        inner: MockClient((request) async {
          seen = request.headers;
          return http.Response('{}', 200);
        }),
      );
      await client.post(Uri.parse('https://x.supabase.co$path'));
      return seen;
    }

    test('function calls are pinned next to the database', () async {
      expect((await headersFor('/functions/v1/chat'))['x-region'],
          'ap-southeast-2');
    });

    test('queries, auth and storage are left alone', () async {
      for (final path in [
        '/rest/v1/profiles',
        '/auth/v1/token',
        '/storage/v1/object/materials/a.txt',
      ]) {
        expect((await headersFor(path)).containsKey('x-region'), isFalse,
            reason: path);
      }
    });

    test('an empty region leaves Supabase to choose', () async {
      expect(
          (await headersFor('/functions/v1/chat', region: ''))
              .containsKey('x-region'),
          isFalse);
    });
  });

  testWidgets('the study-room clock ticks without rebuilding the room',
      (tester) async {
    final store = RoomStore();
    store.applyTimerCommand({
      'action': 'start',
      'phase': 'focus',
      'remaining_secs': 600,
    });

    var roomRebuilds = 0;
    var clockTicks = 0;
    store.addListener(() => roomRebuilds++);
    store.clock.addListener(() => clockTicks++);

    await tester.pump(const Duration(seconds: 3));

    expect(clockTicks, 3);
    expect(roomRebuilds, 0);
    expect(store.secondsLeft, 597);
    expect(store.timerDisplay, '09:57');
    // Here rather than in a tear-down: the ticker has to be gone before the
    // test ends, or the binding reports a pending timer.
    store.dispose();
  });
}

class _Tab extends StatefulWidget {
  const _Tab(this.index, {required this.onBuilt});
  final int index;
  final ValueChanged<int> onBuilt;

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  @override
  void initState() {
    super.initState();
    widget.onBuilt(widget.index);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

HomeStore _home(_Goals goals, {_Roadmap? roadmap}) => HomeStore(
      profiles: const _Profiles(),
      goals: goals,
      tasks: const _Tasks(),
      game: _Game(),
      roadmap: roadmap ?? _Roadmap(),
    );

class _Profiles extends ProfileRepository {
  const _Profiles();
  @override
  Future<Profile?> getMyProfile() async => null;
}

class _Tasks extends TaskRepository {
  const _Tasks();
  @override
  Future<List<DailyTask>> getTodayTasks() async => const [];
}

/// Counts reads in flight at the same moment.
class _Overlap {
  int _active = 0;
  int mostAtOnce = 0;

  Future<T> run<T>(T value) async {
    _active++;
    if (_active > mostAtOnce) mostAtOnce = _active;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    _active--;
    return value;
  }
}

class _Goals extends GoalRepository {
  _Goals({_Overlap? overlap}) : _overlap = overlap ?? _Overlap();
  final _Overlap _overlap;
  int reads = 0;

  @override
  Future<List<Goal>> getGoals() async {
    reads++;
    return const [Goal(id: 'g', name: 'Semester 5', isActive: true)];
  }

  @override
  Future<List<Subject>> getSubjects(String goalId) => _overlap
      .run(const [Subject(id: 's', goalId: 'g', name: 'Operating Systems')]);
}

class _Roadmap extends RoadmapRepository {
  _Roadmap({_Overlap? overlap}) : _overlap = overlap ?? _Overlap();
  final _Overlap _overlap;

  @override
  Future<RoadmapPace> getPace(String goalId) =>
      _overlap.run(const RoadmapPace());
}

/// Each read takes a moment, so reads that overlap are visible.
class _Game extends GamificationRepository {
  _Game({this.failLeaderboard = false});
  final bool failLeaderboard;
  final order = <String>[];
  int _active = 0;
  int mostAtOnce = 0;
  bool _unlocked = false;

  Future<T> _read<T>(String name, T Function() value) async {
    _active++;
    if (_active > mostAtOnce) mostAtOnce = _active;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    _active--;
    order.add(name);
    return value();
  }

  @override
  Future<List<String>> evaluateBadges() => _read('evaluated', () {
        _unlocked = true;
        return const ['first_task'];
      });

  @override
  Future<List<AchievementBadge>> getBadges({bool onlyUnlocked = false}) =>
      _read(
          'badges',
          () => [
                AchievementBadge(
                    id: 'b',
                    key: 'first_task',
                    name: _unlocked ? 'Unlocked just now' : 'Still locked',
                    unlocked: _unlocked),
              ]);

  @override
  Future<Streak> getStreak() =>
      _read('streak', () => const Streak(currentStreak: 4));

  @override
  Future<List<ActivityDay>> getRecentActivity({int days = 60}) =>
      _read('recent', () => const <ActivityDay>[]);

  @override
  Future<List<LeaderboardEntry>> getLeaderboard({int limit = 20}) =>
      _read('leaderboard', () {
        if (failLeaderboard) throw StateError('leaderboard is down');
        return const [
          LeaderboardEntry(userId: 'u', fullName: 'Asha', xp: 120, rank: 1),
        ];
      });
}
