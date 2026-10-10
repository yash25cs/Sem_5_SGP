// Study rooms: the room size picked at creation, the focus length set inside
// the room, and the group quiz everyone takes together.
//
// The store is driven against a fake RoomRepository; the database rules
// (unanimous start, hidden answers, scoring, podium XP) are covered by the
// live probe in the 0019 migration's history, not here.

import 'package:flutter/material.dart' hide MaterialType;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import 'package:studytrail_flutter/data/repositories.dart';
import 'package:studytrail_flutter/models/models.dart';
import 'package:studytrail_flutter/screens/buddy_room_screen.dart';
import 'package:studytrail_flutter/screens/room_quiz_screen.dart';
import 'package:studytrail_flutter/screens/study_room_screen.dart';
import 'package:studytrail_flutter/state/stores.dart';
import 'package:studytrail_flutter/theme/app_theme.dart';

const _host = 'host-id';
const _me = 'me-id';
const _other = 'other-id';

StudyRoom _room({int focus = 25, int brk = 5}) => StudyRoom(
      id: 'r1',
      name: 'DBMS end-sem revision marathon with the whole gang',
      inviteCode: 'ABC123',
      createdBy: _host,
      maxMembers: 3,
      timerDurationMin: focus,
      breakDurationMin: brk,
      createdAt: DateTime(2026, 10, 2),
    );

/// A quiz as `get_room_quiz` returns it, for [_me]. Answers only once it's
/// finished; scores only for [_me] until then.
RoomQuiz _quiz(
  String status, {
  bool? myVote,
  bool iSubmitted = false,
  bool? otherVote,
}) {
  final done = status == 'finished';
  Map<String, dynamic> player(String id, String name,
          {bool? vote, bool submitted = false, int? score, int? rank, int xp = 0}) =>
      {
        'user_id': id,
        'full_name': name,
        'avatar_initial': name[0],
        'vote': vote,
        'submitted': submitted,
        'score': score,
        'rank': rank,
        'xp_awarded': xp,
      };
  return RoomQuiz.fromMap({
    'id': 'q1',
    'room_id': 'r1',
    'created_by': _host,
    'title': 'Unit 3 — Normalisation and functional dependencies quiz',
    'question_count': 2,
    'status': status,
    'players': done
        ? [
            player(_host, 'Aaryanandini Krishnamurthy-Venkataraman',
                vote: true, submitted: true, score: 2, rank: 1, xp: 30),
            player(_me, 'Yash', vote: true, submitted: true, score: 1, rank: 2, xp: 20),
            player(_other, 'Ravi', vote: true),
          ]
        : [
            player(_host, 'Aaryanandini Krishnamurthy-Venkataraman',
                vote: true, submitted: iSubmitted),
            player(_me, 'Yash', vote: myVote, submitted: iSubmitted,
                score: iSubmitted ? 1 : null),
            player(_other, 'Ravi', vote: otherVote),
          ],
    'questions': status == 'voting'
        ? null
        : [
            {
              'id': 'a',
              'question': 'Which normal form removes transitive dependencies '
                  'on a candidate key?',
              'options': ['1NF', '2NF', '3NF', 'BCNF with a lossless join'],
              'correct_index': done ? 2 : null,
              'explanation': done ? '3NF removes transitive dependencies.' : null,
            },
            {
              'id': 'b',
              'question': 'BCNF requires every determinant to be…',
              'options': ['a superkey', 'a foreign key', 'atomic', 'nullable'],
              'correct_index': done ? 0 : null,
              'explanation': null,
            },
          ],
    'my_picks': done || iSubmitted ? {'a': 1, 'b': 0} : null,
  });
}

/// Records what the store asked for and plays the server's part.
class _Rooms extends RoomRepository {
  _Rooms({this.active});

  RoomQuiz? active;
  final calls = <String>[];
  Map<String, int>? handedIn;
  (int, int)? timer;
  int? createdSize;
  (int, int)? createdTimer;

  @override
  Future<List<StudyRoom>> getActiveRooms() async => const [];

  @override
  Future<StudyRoom> createRoom({
    required String name,
    String? classId,
    int timerMin = 25,
    int breakMin = 5,
    int maxMembers = 4,
  }) async {
    createdSize = maxMembers;
    createdTimer = (timerMin, breakMin);
    // Entering would open a realtime channel; stopping here is enough to see
    // what the sheet sent.
    throw 'Stopped by the test.';
  }

  @override
  Future<void> setTimer(String roomId,
      {required int focusMin, required int breakMin}) async {
    timer = (focusMin, breakMin);
  }

  @override
  Future<String> proposeQuiz({
    required String roomId,
    required String materialId,
    required int count,
    bool speed = false,
    int seconds = 20,
  }) async {
    calls.add('propose $materialId $count${speed ? ' speed $seconds' : ''}');
    active = _quiz('voting');
    return 'q1';
  }

  @override
  Future<RoomQuiz?> getActiveQuiz(String roomId) async => active;

  @override
  Future<RoomQuiz> getQuiz(String quizId) async => active!;

  @override
  Future<RoomQuiz> voteQuiz(String quizId, bool agree) async {
    calls.add('vote $agree');
    return active = _quiz(agree ? 'running' : 'cancelled',
        myVote: agree, otherVote: agree ? true : null);
  }

  @override
  Future<RoomQuiz> submitQuiz(String quizId, Map<String, int> picks) async {
    handedIn = picks;
    return active = _quiz('running', myVote: true, otherVote: true, iSubmitted: true);
  }

  @override
  Future<RoomQuiz> endQuiz(String quizId) async {
    calls.add('end');
    return active = _quiz('finished');
  }
}

RoomStore _store(_Rooms repo, {String user = _me}) =>
    RoomStore(roomRepo: repo, quizPollInterval: null)..debugUserId = user;

void main() {
  group('RoomQuiz parsing', () {
    test('a running quiz carries the questions but not the answers', () {
      final q = _quiz('running', myVote: true, otherVote: true);
      expect(q.running, isTrue);
      expect(q.questions, hasLength(2));
      expect(q.questions.every((x) => x.correctIndex == null), isTrue);
      expect(q.myPicks, isEmpty);
      expect(q.player(_me)?.score, isNull);
    });

    test('a finished quiz carries ranks, scores, XP and the answers', () {
      final q = _quiz('finished');
      expect(q.questions.first.correctIndex, 2);
      expect(q.myPicks, {'a': 1, 'b': 0});
      expect([for (final p in q.players) (p.rank, p.score, p.xpAwarded)],
          [(1, 2, 30), (2, 1, 20), (null, null, 0)]);
      expect(q.submittedCount, 2);
    });
  });

  group('RoomStore group quiz', () {
    test('a quiz already being voted on shows on entering', () async {
      final store = _store(_Rooms(active: _quiz('voting')));
      addTearDown(store.dispose);

      await store.debugEnterRoomWithoutChannel(_room());

      expect(store.quiz?.voting, isTrue);
      expect(store.quiz?.player(_me)?.vote, isNull);
    });

    test('agree, answer, hand in: the picks go to the server once', () async {
      final repo = _Rooms(active: _quiz('voting'));
      final store = _store(repo);
      addTearDown(store.dispose);
      await store.debugEnterRoomWithoutChannel(_room());

      expect(await store.voteQuiz(true), isTrue);
      expect(store.quiz?.running, isTrue);

      store.pickAnswer('a', 1);
      store.pickAnswer('a', 2); // changed their mind
      store.pickAnswer('b', 0);
      expect(store.draftPicks, {'a': 2, 'b': 0});

      expect(await store.submitQuiz(), isTrue);
      expect(repo.handedIn, {'a': 2, 'b': 0});
      expect(store.quiz?.player(_me)?.submitted, isTrue);

      // Handed in: no more changes.
      store.pickAnswer('a', 3);
      expect(store.draftPicks['a'], 2);
    });

    test('one "not now" cancels, and closing the card keeps it closed',
        () async {
      final repo = _Rooms(active: _quiz('voting'));
      final store = _store(repo);
      addTearDown(store.dispose);
      await store.debugEnterRoomWithoutChannel(_room());

      await store.voteQuiz(false);
      expect(store.quiz?.cancelled, isTrue);

      store.dismissQuiz();
      expect(store.quiz, isNull);
      // The server keeps offering the last quiz for a while; a refresh must
      // not bring a closed card back.
      repo.active = _quiz('finished');
      await store.refreshQuiz();
      expect(store.quiz, isNull);
    });

    test('an open quiz cannot be dismissed', () async {
      final store = _store(_Rooms(active: _quiz('voting')));
      addTearDown(store.dispose);
      await store.debugEnterRoomWithoutChannel(_room());

      store.dismissQuiz();
      expect(store.quiz?.voting, isTrue);
    });

    test('only the host proposes or ends a quiz', () async {
      final repo = _Rooms();
      final member = _store(repo);
      addTearDown(member.dispose);
      await member.debugEnterRoomWithoutChannel(_room());

      expect(await member.proposeQuiz(materialId: 'm1', count: 10), isFalse);
      expect(repo.calls, isEmpty);

      final host = _store(repo, user: _host);
      addTearDown(host.dispose);
      await host.debugEnterRoomWithoutChannel(_room());

      expect(await host.proposeQuiz(materialId: 'm1', count: 10), isTrue);
      expect(repo.calls, ['propose m1 10']);
      expect(host.quiz?.voting, isTrue);
      expect(host.quizWorking, isFalse);

      await member.refreshQuiz();
      expect(await member.endQuiz(), isFalse);
      expect(await host.endQuiz(), isTrue);
      expect(host.quiz?.finished, isTrue);
    });
  });

  group('RoomStore focus length', () {
    test('the host sets it inside the room, with the clock stopped', () async {
      final repo = _Rooms();
      final store = _store(repo, user: _host)..debugEnterRoomOffline(_room());
      addTearDown(store.dispose);

      expect(await store.setTimerLengths(focusMin: 45, breakMin: 10), isTrue);
      expect(repo.timer, (45, 10));
      expect(store.currentRoom?.timerDurationMin, 45);
      expect(store.currentRoom?.breakDurationMin, 10);
      expect(store.secondsLeft, 45 * 60);
      expect(store.timerDisplay, '45:00');

      store.startTimer();
      repo.timer = null;
      expect(await store.setTimerLengths(focusMin: 25, breakMin: 5), isFalse);
      expect(repo.timer, isNull);
    });

    test('a member cannot change it', () async {
      final repo = _Rooms();
      final store = _store(repo)..debugEnterRoomOffline(_room());
      addTearDown(store.dispose);

      expect(await store.setTimerLengths(focusMin: 45, breakMin: 10), isFalse);
      expect(repo.timer, isNull);
    });

    test("members follow the host's new lengths into the next phase", () {
      final store = _store(_Rooms())..debugEnterRoomOffline(_room());
      addTearDown(store.dispose);

      store.applyTimerCommand({
        'action': 'reset',
        'phase': 'focus',
        'remaining_secs': 2700,
        'total_secs': 2700,
        'focus_min': 45,
        'break_min': 10,
      });
      expect(store.currentRoom?.timerDurationMin, 45);
      expect(store.secondsLeft, 2700);

      // No total in the message: the break length comes from the room.
      store.applyTimerCommand({'action': 'switch_phase', 'phase': 'break'});
      expect(store.totalSeconds, 10 * 60);
    });
  });

  // ── Layout at 320 dp ──────────────────────────────────────────────────────

  Future<void> pumpNarrow(WidgetTester tester, Widget child,
      List<ChangeNotifierProvider> providers) async {
    tester.view.physicalSize = const Size(320 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: providers,
      child: MaterialApp(theme: AppTheme.light(), home: child),
    ));
    await tester.pumpAndSettle();
  }

  for (final (label, quiz, user, expected) in [
    ('no quiz yet, host', null, _host, 'Start a group quiz'),
    ('no quiz yet, member', null, _me, 'Group quiz'),
    ('voting, my turn', _quiz('voting'), _me, "I'm in"),
    ('voting, host', _quiz('voting', myVote: true), _host, 'Cancel quiz'),
    ('running', _quiz('running', myVote: true, otherVote: true), _me, 'Start the quiz'),
    ('running, handed in',
        _quiz('running', myVote: true, otherVote: true, iSubmitted: true), _host,
        'End quiz now'),
    ('finished', _quiz('finished'), _me, 'Results'),
    ('cancelled', _quiz('cancelled', myVote: true, otherVote: false), _me,
        'Quiz cancelled'),
  ]) {
    testWidgets('room screen fits: $label', (tester) async {
      final store = _store(_Rooms(active: quiz), user: user);
      await store.debugEnterRoomWithoutChannel(_room());
      await pumpNarrow(tester, const StudyRoomScreen(),
          [ChangeNotifierProvider<RoomStore>.value(value: store)]);

      expect(find.text(expected), findsOneWidget);
      expect(find.text('25 min focus'), findsOneWidget);
      expect(find.text('Change'), user == _host ? findsOneWidget : findsNothing);
      addTearDown(store.dispose);
    });
  }

  testWidgets('answering: same questions, picks kept, hand in', (tester) async {
    final repo = _Rooms(active: _quiz('running', myVote: true, otherVote: true));
    final store = _store(repo);
    await store.debugEnterRoomWithoutChannel(_room());
    await pumpNarrow(tester, const RoomQuizScreen(),
        [ChangeNotifierProvider<RoomStore>.value(value: store)]);

    expect(find.text('Question 1 of 2'), findsOneWidget);
    await tester.tap(find.text('3NF'));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('a superkey'));
    await tester.tap(find.text('Hand in'));
    await tester.pumpAndSettle();

    expect(repo.handedIn, {'a': 2, 'b': 0});
    expect(find.text('Handed in!'), findsOneWidget);
    addTearDown(store.dispose);
  });

  testWidgets('answers fit once the quiz is over', (tester) async {
    final store = _store(_Rooms(active: _quiz('finished')));
    await store.debugEnterRoomWithoutChannel(_room());
    await pumpNarrow(tester, const RoomQuizScreen(),
        [ChangeNotifierProvider<RoomStore>.value(value: store)]);

    expect(find.textContaining('You got 1 of 2'), findsOneWidget);
    addTearDown(store.dispose);
  });

  testWidgets('creating a room asks for a size, not a timer', (tester) async {
    final repo = _Rooms();
    final rooms = _store(repo);
    addTearDown(rooms.dispose);
    final profiles =
        ProfileStore(profiles: const _Profiles(), goals: const _Goals());
    final game =
        GamificationStore(game: const _Game(), profiles: const _Profiles());
    await pumpNarrow(tester, const BuddyRoomScreen(), [
      ChangeNotifierProvider<RoomStore>.value(value: rooms),
      ChangeNotifierProvider<ProfileStore>.value(value: profiles),
      ChangeNotifierProvider<GamificationStore>.value(value: game),
    ]);

    await tester.tap(find.byIcon(Symbols.add));
    await tester.pumpAndSettle();

    expect(find.text('How many people?'), findsOneWidget);
    expect(find.text('Focus Duration'), findsNothing);
    expect(find.text('Break Duration'), findsNothing);
    for (final n in RoomStore.roomSizes) {
      expect(find.byKey(ValueKey('room-size-$n')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('room-size-7')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('room-size-6')));
    await tester.pump();
    await tester.tap(find.text('Create & Enter Room'));
    await tester.pumpAndSettle();

    expect(repo.createdSize, 6);
    // The timer starts at the defaults; the host changes it inside the room.
    expect(repo.createdTimer, (25, 5));
  });
}

class _Profiles extends ProfileRepository {
  const _Profiles();
  @override
  Future<Profile?> getMyProfile() async => null;
  @override
  Future<List<Map<String, dynamic>>> getClasses() async => const [];
}

class _Goals extends GoalRepository {
  const _Goals();
  @override
  Future<List<Goal>> getGoals() async => const [];
}

class _Game extends GamificationRepository {
  const _Game();
  @override
  Future<List<String>> evaluateBadges() async => const [];
  @override
  Future<Streak> getStreak() async => const Streak();
  @override
  Future<List<AchievementBadge>> getBadges({bool onlyUnlocked = false}) async =>
      const [];
  @override
  Future<List<ActivityDay>> getRecentActivity({int days = 60}) async =>
      const [];
  @override
  Future<List<LeaderboardEntry>> getLeaderboard({int limit = 20}) async =>
      const [];
  @override
  Future<RewardWallet> getRewardWallet() async =>
      const RewardWallet(earned: 0, spent: 0, balance: 0, rewards: []);
}
