// Tests for the study-room timer sync and the rewards/leaderboard parsing.
//
// The room timer is pure state once a broadcast arrives, so these drive
// `RoomStore.applyTimerCommand` directly — no channel, no network.

import 'package:flutter_test/flutter_test.dart';

import 'package:studytrail_flutter/data/repositories.dart';
import 'package:studytrail_flutter/models/models.dart';
import 'package:studytrail_flutter/state/stores.dart';

void main() {
  group('RoomStore timer broadcasts', () {
    // realtime_client hands a broadcast callback the whole message. Reading
    // `action` off the top level is what zeroed every member's timer.
    test('the app data is read from under `payload`', () {
      final data = RoomStore.unwrapBroadcast({
        'type': 'broadcast',
        'event': 'timer',
        'payload': {'action': 'start', 'remaining_secs': 900},
      });
      expect(data['action'], 'start');
      expect(data['remaining_secs'], 900);
    });

    test('a host start sets the time and runs the clock', () {
      final store = RoomStore();
      addTearDown(store.dispose);

      store.applyTimerCommand({
        'action': 'start',
        'phase': 'focus',
        'remaining_secs': 1200,
        'total_secs': 1500,
      });

      expect(store.timerRunning, isTrue);
      expect(store.secondsLeft, 1200);
      expect(store.totalSeconds, 1500);
      expect(store.timerDisplay, '20:00');
    });

    // A late joiner gets `sync`, which carries whether the clock is running —
    // the one action whose meaning depends on the payload.
    test('sync follows the host whether paused or running', () {
      final store = RoomStore();
      addTearDown(store.dispose);

      store.applyTimerCommand({
        'action': 'sync',
        'phase': 'break',
        'remaining_secs': 120,
        'total_secs': 300,
        'running': false,
      });
      expect(store.timerRunning, isFalse);
      expect(store.isFocus, isFalse);
      expect(store.secondsLeft, 120);

      store.applyTimerCommand({
        'action': 'sync',
        'phase': 'break',
        'remaining_secs': 119,
        'total_secs': 300,
        'running': true,
      });
      expect(store.timerRunning, isTrue);
    });

    test('pause stops the clock at the host\'s time', () {
      final store = RoomStore();
      addTearDown(store.dispose);

      store.applyTimerCommand(
          {'action': 'start', 'phase': 'focus', 'remaining_secs': 600});
      store.applyTimerCommand(
          {'action': 'pause', 'phase': 'focus', 'remaining_secs': 540});

      expect(store.timerRunning, isFalse);
      expect(store.secondsLeft, 540);
    });

    test('a message without an action changes nothing', () {
      final store = RoomStore();
      addTearDown(store.dispose);
      final before = store.secondsLeft;

      store.applyTimerCommand({'remaining_secs': 0});

      expect(store.secondsLeft, before);
      expect(store.timerRunning, isFalse);
    });
  });

  test('message ids are v4 UUIDs, unique per call', () {
    final a = RoomRepository.newMessageId();
    final b = RoomRepository.newMessageId();
    final v4 = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
    expect(v4.hasMatch(a), isTrue, reason: a);
    expect(a, isNot(b));
  });

  group('Leaderboard and wallet parsing', () {
    test('ranks read total XP, and fall back to xp on an older database', () {
      final now = LeaderboardEntry.fromMap({
        'user_id': 'u1',
        'full_name': 'Asha',
        'level': 2,
        'xp': 20,
        'total_xp': 520,
        'golden_border': true,
        'is_me': true,
      }, rank: 1);
      expect(now.totalXp, 520);
      expect(now.xp, 20);
      expect(now.goldenBorder, isTrue);

      final legacy = LeaderboardEntry.fromMap(
          {'user_id': 'u2', 'full_name': 'Ravi', 'xp': 90},
          rank: 2);
      expect(legacy.totalXp, 90);
      expect(legacy.goldenBorder, isFalse);
    });

    test('a wallet knows what is held and what is at its cap', () {
      final w = RewardWallet.fromMap({
        'earned': 526,
        'spent': 300,
        'balance': 226,
        'rewards': [
          {
            'key': 'streak_freeze',
            'title': 'Streak Freeze',
            'description': 'Covers one missed day.',
            'cost_xp': 100,
            'max_held': 2,
            'held': 2,
            'used': 1,
          },
          {
            'key': 'golden_border',
            'title': 'Golden Scholar Border',
            'description': 'A gold ring.',
            'cost_xp': 300,
            'max_held': 1,
            'held': 0,
            'used': 0,
          },
        ],
      });

      expect(w.balance, 226);
      expect(w.rewards, hasLength(2));
      expect(w.rewards.first.atCap, isTrue);
      expect(w.rewards.first.used, 1);
      expect(w.rewards.last.atCap, isFalse);
    });
  });
}
