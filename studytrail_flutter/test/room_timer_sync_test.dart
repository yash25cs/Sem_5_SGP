// The shared room timer staying in step, and members asking the host to pause.
//
// The store is driven without a channel: host messages go through
// `applyTimerCommand`, requests and answers through `onTimerRequestData` /
// `onTimerAnswerData`, the same functions the channel callbacks call.

import 'package:flutter/material.dart' hide MaterialType;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:studytrail_flutter/data/repositories.dart';
import 'package:studytrail_flutter/models/models.dart';
import 'package:studytrail_flutter/screens/study_room_screen.dart';
import 'package:studytrail_flutter/state/stores.dart';
import 'package:studytrail_flutter/theme/app_theme.dart';

const _host = 'host-id';
const _me = 'me-id';

StudyRoom _room() => StudyRoom(
      id: 'r1',
      name: 'Focus room',
      inviteCode: 'ABC123',
      createdBy: _host,
      createdAt: DateTime(2026, 10, 11),
    );

class _Rooms extends RoomRepository {
  @override
  Future<RoomQuiz?> getActiveQuiz(String roomId) async => null;

  @override
  Future<List<RoomSharedMaterial>> getSharedMaterials(String roomId) async =>
      const [];
}

RoomStore _store(String user) =>
    RoomStore(roomRepo: _Rooms(), quizPollInterval: null, timerHeartbeat: null)
      ..debugUserId = user;

Map<String, dynamic> _cmd(String action,
        {required int seq, bool running = false, int remaining = 1200}) =>
    {
      'seq': seq,
      'action': action,
      'phase': 'focus',
      'remaining_secs': remaining,
      'total_secs': 1500,
      'running': running,
    };

void main() {
  group('Keeping members in step', () {
    late RoomStore member;

    setUp(() {
      member = _store(_me)..debugEnterRoomOffline(_room());
    });
    tearDown(() => member.dispose());

    test('a heartbeat puts right a resume this phone missed', () {
      member.applyTimerCommand(_cmd('pause', seq: 100));
      expect(member.timerRunning, isFalse);
      // The "resume" never arrived; the next heartbeat says it's running.
      member.applyTimerCommand(
          _cmd('sync', seq: 300, running: true, remaining: 1180));
      expect(member.timerRunning, isTrue);
      expect(member.secondsLeft, 1180);
    });

    test('an older message arriving late is ignored', () {
      member.applyTimerCommand(_cmd('resume', seq: 200, running: true));
      member.applyTimerCommand(_cmd('pause', seq: 100));
      expect(member.timerRunning, isTrue,
          reason: 'the pause was sent before the resume');
    });

    test('a heartbeat that agrees changes nothing', () {
      member.applyTimerCommand(
          _cmd('start', seq: 100, running: true, remaining: 1200));
      var redraws = 0;
      member.addListener(() => redraws++);
      member.applyTimerCommand(
          _cmd('sync', seq: 200, running: true, remaining: 1199));
      expect(redraws, 0);
      expect(member.secondsLeft, 1200);
    });

    test('a heartbeat that has drifted is corrected', () {
      member.applyTimerCommand(
          _cmd('start', seq: 100, running: true, remaining: 1200));
      member.applyTimerCommand(
          _cmd('sync', seq: 200, running: true, remaining: 1100));
      expect(member.secondsLeft, 1100);
    });

    test('messages without a seq (older builds) still apply', () {
      member.applyTimerCommand(_cmd('resume', seq: 500, running: true)
        ..remove('seq'));
      expect(member.timerRunning, isTrue);
    });
  });

  group('Asking to pause', () {
    test('the host sees each request once; pausing answers them all', () {
      final host = _store(_host)..debugEnterRoomOffline(_room());
      addTearDown(host.dispose);
      host.startTimer();

      host.onTimerRequestData(
          {'kind': 'pause', 'user_id': _me, 'name': 'Yash Patel'});
      host.onTimerRequestData(
          {'kind': 'pause', 'user_id': _me, 'name': 'Yash Patel'});
      host.onTimerRequestData(
          {'kind': 'pause', 'user_id': 'ravi', 'name': 'Ravi'});
      expect(host.pauseRequests.map((r) => r.name), ['Yash Patel', 'Ravi']);

      host.pauseTimer();
      expect(host.timerRunning, isFalse);
      expect(host.pauseRequests, isEmpty);
    });

    test('Not now drops one request and keeps the timer running', () {
      final host = _store(_host)..debugEnterRoomOffline(_room());
      addTearDown(host.dispose);
      host.startTimer();
      host.onTimerRequestData({'kind': 'pause', 'user_id': _me, 'name': 'Y'});
      host.declinePause(_me);
      expect(host.pauseRequests, isEmpty);
      expect(host.timerRunning, isTrue);
    });

    test('members ignore requests; the host ignores answers', () {
      final member = _store(_me)..debugEnterRoomOffline(_room());
      addTearDown(member.dispose);
      member.onTimerRequestData({'kind': 'pause', 'user_id': 'x', 'name': 'X'});
      expect(member.pauseRequests, isEmpty);
    });

    test('the member is told what the host decided', () {
      final member = _store(_me)..debugEnterRoomOffline(_room());
      addTearDown(member.dispose);
      member.onTimerAnswerData({'user_id': 'someone-else', 'accepted': true});
      expect(member.timerNotice, isNull);
      member.onTimerAnswerData({'user_id': _me, 'accepted': false});
      expect(member.timerNotice, 'The host kept the timer running.');
      member.clearTimerNotice();
      member.onTimerAnswerData({'user_id': _me, 'accepted': true});
      expect(member.timerNotice, 'The host paused the timer.');
    });

    test("can't ask while paused, or without a connection", () {
      final member = _store(_me)..debugEnterRoomOffline(_room());
      addTearDown(member.dispose);
      expect(member.requestPause(), isFalse);
      expect(member.error, contains('already paused'));
      member.applyTimerCommand(_cmd('start', seq: 1, running: true));
      expect(member.requestPause(), isFalse);
      expect(member.error, contains('Not connected'));
      expect(member.pauseRequested, isFalse);
    });
  });

  group('Room screen at 320 dp', () {
    Future<void> pump(WidgetTester tester, RoomStore store) async {
      tester.view.physicalSize = const Size(320 * 3, 900 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ChangeNotifierProvider<RoomStore>.value(
        value: store,
        child:
            MaterialApp(theme: AppTheme.light(), home: const StudyRoomScreen()),
      ));
      await tester.pump();
    }

    testWidgets('a member sees Ask host to pause while it runs',
        (tester) async {
      final member = _store(_me);
      await member.debugEnterRoomWithoutChannel(_room());
      member.applyTimerCommand(_cmd('start', seq: 1, running: true));
      await pump(tester, member);
      expect(find.text('Ask host to pause'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      member.dispose();
    });

    testWidgets('the host sees the request with Pause and Not now',
        (tester) async {
      final host = _store(_host);
      await host.debugEnterRoomWithoutChannel(_room());
      host.startTimer();
      host.onTimerRequestData(
          {'kind': 'pause', 'user_id': _me, 'name': 'Aaryanandini Krishnamurthy'});
      await pump(tester, host);
      expect(find.text('Aaryanandini asks to pause'), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);

      await tester.tap(find.text('Not now'));
      await tester.pump();
      expect(find.text('Aaryanandini asks to pause'), findsNothing);
      expect(host.timerRunning, isTrue);
      await tester.pumpWidget(const SizedBox());
      host.dispose();
    });
  });
}
