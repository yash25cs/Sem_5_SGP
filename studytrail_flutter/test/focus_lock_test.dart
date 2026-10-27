// The locked focus session and the timer bar above the navigator.
//
// A running focus block can't be left: back opens the end-early sheet, which
// only ends the block once "won't be counted" is ticked, and an ended block
// logs nothing. The bar above the navigator used to hold a tooltip, which has
// no Overlay up there and put a red error screen over the whole app.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:studytrail_flutter/data/repositories.dart';
import 'package:studytrail_flutter/models/models.dart';
import 'package:studytrail_flutter/screens/pomodoro_screen.dart';
import 'package:studytrail_flutter/services/notification_service.dart';
import 'package:studytrail_flutter/state/stores.dart';
import 'package:studytrail_flutter/theme/app_theme.dart';
import 'package:studytrail_flutter/widgets/timer_banner.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('back is refused; ending needs the tick and counts nothing',
      (tester) async {
    final game = _FakeGame();
    final notices = _FakeNotices();
    final store = _store(game, notices);
    await _pumpApp(tester, store);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    store.start();
    await tester.pump();
    expect(store.locked, isTrue);
    expect(notices.showing, isTrue);
    expect(notices.lastTitle, 'Focus session running');

    // Stop, reset and switching mode would all end the block unconfirmed.
    // One tick first: a block paused at its full length was never begun.
    await tester.pump(const Duration(seconds: 1));
    store.pause();
    await tester.pump();
    expect(notices.lastTitle, 'Focus session paused');
    store.stop();
    store.reset();
    expect(store.switchTo(PomodoroPhase.shortBreak), isFalse);
    expect(store.locked, isTrue);
    store.start();
    await tester.pump();

    // The screen's own back button: opens the sheet, "Keep focusing" stays.
    await tester.tap(find.byIcon(Symbols.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('End this focus block?'), findsOneWidget);
    await tester.tap(find.text('Keep focusing'));
    await tester.pumpAndSettle();
    expect(find.byType(PomodoroScreen), findsOneWidget);
    expect(store.locked, isTrue);

    // System (and predictive) back goes through PopScope.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(PomodoroScreen), findsOneWidget);
    expect(find.text('End this focus block?'), findsOneWidget);

    // Not ticked: the button does nothing.
    await tester.tap(find.text('End session'));
    await tester.pumpAndSettle();
    expect(find.text('End this focus block?'), findsOneWidget);
    expect(store.locked, isTrue);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('End session'));
    await tester.pumpAndSettle();

    expect(find.byType(PomodoroScreen), findsNothing);
    expect(find.text('open'), findsOneWidget);
    expect(store.locked, isFalse);
    expect(store.inProgress, isFalse);
    expect(notices.showing, isFalse);

    // Long after the block would have finished, still nothing logged.
    await tester.pump(const Duration(minutes: 30));
    expect(game.sessions, isEmpty);
    expect(store.sessionsToday, 0);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a block that runs out still counts and clears the notice',
      (tester) async {
    final game = _FakeGame();
    final notices = _FakeNotices();
    final store = _store(game, notices);
    addTearDown(store.dispose);

    await store.applyPreset(const TimerPreset(
        id: 't', label: 'Short', focusMinutes: 1, breakMinutes: 1));
    store.start();
    await tester.pump();
    expect(notices.showing, isTrue);

    await tester.pump(const Duration(seconds: 61));
    expect(game.sessions, [(1, 1)]);
    expect(store.sessionsToday, 1);
    // The break that follows isn't locked and has no notice.
    expect(store.isFocus, isFalse);
    expect(store.locked, isFalse);
    expect(notices.showing, isFalse);

    store.stop();
  });

  testWidgets(
      'the bar above the navigator renders, and a locked block '
      'brings its screen back', (tester) async {
    final notices = _FakeNotices();
    final store = _store(_FakeGame(), notices);
    await _pumpApp(tester, store);

    // A break running off the timer screen shows the bar — this is what threw
    // "No Overlay widget found" and overflowed by ~99,000 px.
    store.switchTo(PomodoroPhase.shortBreak);
    store.start();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text(store.display), findsOneWidget);
    expect(find.byType(PomodoroScreen), findsNothing);

    // Tapping the bar opens the timer.
    await tester.tap(find.text(store.display));
    await tester.pumpAndSettle();
    expect(find.byType(PomodoroScreen), findsOneWidget);
    store.stop();
    await tester.pump();
    Navigator.of(tester.element(find.byType(PomodoroScreen))).pop();
    await tester.pumpAndSettle();

    // A focus block running with no timer screen up is put back on screen.
    store.start();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(PomodoroScreen), findsOneWidget);

    store.endEarly();
    await tester.pumpWidget(const SizedBox());
  });
}

PomodoroStore _store(_FakeGame game, _FakeNotices notices) =>
    PomodoroStore(game: game, goals: const _NoGoals(), notifications: notices);

Future<void> _pumpApp(WidgetTester tester, PomodoroStore store) async {
  final key = GlobalKey<NavigatorState>();
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: store,
    child: MaterialApp(
      navigatorKey: key,
      theme: AppTheme.light(),
      builder: (context, navigator) =>
          PomodoroOverlay(navigatorKey: key, child: navigator!),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PomodoroScreen(
                      onBack: () => Navigator.of(context).pop()))),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ));
}

class _FakeGame extends GamificationRepository {
  final sessions = <(int, int)>[];

  @override
  Future<List<StudySession>> getStudySessions({int limit = 50}) async =>
      const [];

  @override
  Future<StudySession> recordSession({
    String? subjectId,
    int? lengthMin,
    int? focusedMin,
  }) async {
    sessions.add((lengthMin ?? 0, focusedMin ?? 0));
    return StudySession(id: 's', sessionDate: DateTime(2026, 10, 27));
  }
}

class _NoGoals extends GoalRepository {
  const _NoGoals();

  @override
  Future<Goal?> getActiveGoal() async => null;
}

class _FakeNotices extends NotificationService {
  _FakeNotices() : super.forTesting();

  bool showing = false;
  String? lastTitle;

  @override
  Future<void> requestPermissions() async {}

  @override
  Future<void> showFocusSession({
    required String title,
    required String body,
    DateTime? endsAt,
  }) async {
    showing = true;
    lastTitle = title;
  }

  @override
  Future<void> cancelFocusSession() async => showing = false;
}
