// Speed rounds, the calendar export, the weekly report, the doubt board, and
// how their screens fit a 320-dp phone.

import 'package:flutter/material.dart' hide MaterialType;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:studytrail_flutter/data/repositories.dart';
import 'package:studytrail_flutter/models/models.dart';
import 'package:studytrail_flutter/screens/doubt_board_screen.dart';
import 'package:studytrail_flutter/screens/room_quiz_screen.dart';
import 'package:studytrail_flutter/screens/weekly_report_screen.dart';
import 'package:studytrail_flutter/services/calendar_export.dart';
import 'package:studytrail_flutter/state/stores.dart';
import 'package:studytrail_flutter/theme/app_theme.dart';

void main() {
  group('SpeedClock', () {
    final start = DateTime.utc(2026, 10, 2, 10);
    SpeedClock at(double seconds) => SpeedClock.at(
        start.add(Duration(milliseconds: (seconds * 1000).round())), start, 20);

    test('a 5 s lead before the first question', () {
      final c = at(2);
      expect(c.lead, isTrue);
      expect(c.secondsLeft, closeTo(3, 0.001));
    });

    test('then 20 s to answer, then a 4 s reveal, per question', () {
      expect(at(5).index, 0);
      expect(at(5).answering, isTrue);
      expect(at(24.9).answering, isTrue);
      expect(at(25).revealing, isTrue);
      expect(at(28.9).index, 0);
      expect(at(29).index, 1);
      expect(at(29).answering, isTrue);
      expect(at(30).secondsLeft, closeTo(19, 0.001));
    });

    test("is drawn on the server's clock, not the phone's", () {
      // The phone runs 3 s behind the server.
      final quiz = RoomQuiz(
        id: 'q',
        roomId: 'r',
        createdBy: 'h',
        title: 'T',
        questionCount: 3,
        status: 'running',
        mode: 'speed',
        secondsPerQuestion: 20,
        startedAt: start,
        clockOffset: const Duration(seconds: 3),
      );
      // Server time is start + 6 s: 1 s into question 1, after the 5 s lead.
      final phoneNow = start.add(const Duration(seconds: 3));
      expect(quiz.clockAt(phoneNow)!.inSlot, closeTo(1, 0.001));
      expect(quiz.clockAt(phoneNow)!.index, 0);
    });

    test('a standard quiz has no clock', () {
      const quiz = RoomQuiz(
          id: 'q',
          roomId: 'r',
          createdBy: 'h',
          title: 'T',
          questionCount: 3,
          status: 'running');
      expect(quiz.clockAt(DateTime.now()), isNull);
    });
  });

  group('CalendarExport', () {
    final now = DateTime.utc(2026, 10, 2, 8, 30);
    final goal = Goal(
      id: 'g1',
      name: 'Sem 5, end-sem; DBMS & ML',
      examDate: DateTime(2026, 11, 30),
      roadmapStartedOn: DateTime(2026, 10, 5),
    );

    test('one all-day event per subject exam, with two reminders', () {
      final ics = CalendarExport.build(
        goals: [goal],
        subjectsByGoal: {
          'g1': [
            Subject(id: 's1', name: 'DBMS', examDate: DateTime(2026, 11, 20)),
            const Subject(id: 's2', name: 'ML'),
          ],
        },
        now: now,
      );
      expect(ics, startsWith('BEGIN:VCALENDAR\r\n'));
      expect(ics, endsWith('END:VCALENDAR\r\n'));
      expect(ics, contains('UID:exam-s1@studytrail'));
      expect(ics, contains('DTSTART;VALUE=DATE:20261120'));
      expect(ics, contains('DTEND;VALUE=DATE:20261121'));
      expect(ics, contains('TRIGGER:-P7D'));
      expect(ics, contains('TRIGGER:-P1D'));
      // A dated subject makes the goal's own date redundant.
      expect(ics, isNot(contains('goal-g1')));
      expect(ics, contains('DTSTAMP:20261002T083000Z'));
    });

    test("the goal's date stands in when no subject has one", () {
      final ics = CalendarExport.build(goals: [goal], now: now);
      expect(ics, contains('UID:goal-g1@studytrail'));
      // Commas and semicolons are escaped in TEXT values.
      expect(ics, contains(r'SUMMARY:Exam: Sem 5\, end-sem\; DBMS & ML'));
    });

    test('roadmap weeks span seven days from the start, in order', () {
      final ics = CalendarExport.build(
        goals: const [],
        roadmapGoal: goal,
        milestones: const [
          Milestone(id: 'm2', title: 'Indexing', orderIndex: 1),
          Milestone(
              id: 'm1',
              title: 'Normalisation',
              weekLabel: 'Week 1',
              orderIndex: 0,
              tasks: [MilestoneTask(id: 't', name: 'Revise 3NF')]),
        ],
        now: now,
      );
      final w1 = ics.indexOf('UID:week-m1');
      final w2 = ics.indexOf('UID:week-m2');
      expect(w1, lessThan(w2));
      expect(ics, contains('SUMMARY:Week 1: Normalisation'));
      expect(ics, contains('DTSTART;VALUE=DATE:20261005'));
      expect(ics, contains('DTEND;VALUE=DATE:20261012'));
      expect(ics, contains('SUMMARY:Week 2: Indexing'));
      expect(ics, contains(r'DESCRIPTION:• Revise 3NF'));
    });

    test('long lines fold at 75 octets without splitting a character', () {
      final ics = CalendarExport.build(
        goals: const [],
        tasks: [
          DailyTask(
              id: 't1',
              title: 'નોર્મલાઇઝેશન ' * 12,
              scheduledDate: DateTime(2026, 10, 3)),
        ],
        now: now,
      );
      final summary = ics
          .split('\r\n')
          .skipWhile((l) => !l.startsWith('SUMMARY:Study:'))
          .takeWhile((l) => l.startsWith('SUMMARY') || l.startsWith(' '))
          .toList();
      expect(summary.length, greaterThan(1));
      for (final l in summary) {
        expect(const Utf8Length().of(l), lessThanOrEqualTo(75));
      }
      // Unfolded, it reads back as written.
      final unfolded =
          summary.first + summary.skip(1).map((l) => l.substring(1)).join();
      expect(unfolded, 'SUMMARY:Study: ${'નોર્મલાઇઝેશન ' * 12}');
    });
  });

  test('the weekly report parses this week, last week and the units', () {
    final r = WeeklyReport.fromMap(_report);
    expect(r.thisWeek.minutes, 145);
    expect(r.thisWeek.quizAccuracy, closeTo(0.75, 0.001));
    expect(r.lastWeek.quizAccuracy, isNull);
    expect(r.days, hasLength(7));
    expect(r.units.first.unitLabel, startsWith('Unit 2'));
    expect(r.units.first.accuracyBefore, closeTo(0.5, 0.001));
    expect(r.streak, 4);
    expect(r.mistakesDue, 6);
    expect(r.empty, isFalse);
  });

  group('DoubtStore', () {
    test('posting opens the doubt and refreshes the board', () async {
      final repo = _Doubts();
      final store = DoubtStore(doubts: repo);
      addTearDown(store.dispose);

      final id = await store.post(title: 'What is BCNF exactly?');
      expect(id, 'd1');
      expect(store.thread?.title, 'What is BCNF exactly?');
      expect(store.doubts.map((d) => d.id), ['d1']);
    });

    test('answering, voting and marking solved update the open doubt',
        () async {
      final repo = _Doubts();
      final store = DoubtStore(doubts: repo);
      addTearDown(store.dispose);
      await store.post(title: 'What is BCNF exactly?');

      expect(
          await store.answer('Every determinant is a candidate key.'), isTrue);
      expect(store.thread?.answers, hasLength(1));
      final a = store.thread!.answers.first.id;
      await store.vote(a);
      expect(store.thread!.answers.first.votes, 1);
      await store.markSolved(a);
      expect(store.thread!.solved, isTrue);
    });

    test('a student without a class is told to join one', () async {
      final store = DoubtStore(doubts: _Doubts(noClass: true));
      addTearDown(store.dispose);
      await store.load();
      expect(store.error, contains('Join your class'));
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
    await tester.pump();
    await tester.pump();
  }

  testWidgets('the weekly report fits', (tester) async {
    final store = WeeklyReportStore(game: _Game());
    addTearDown(store.dispose);
    await pumpNarrow(tester, const WeeklyReportScreen(),
        [ChangeNotifierProvider<WeeklyReportStore>.value(value: store)]);
    expect(find.text('Focused this week'), findsOneWidget);
    expect(find.text('2 h 25 min'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Needs work'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Needs work'), findsOneWidget);
  });

  testWidgets('the doubt board and a doubt fit', (tester) async {
    final store = DoubtStore(doubts: _Doubts(seeded: true));
    addTearDown(store.dispose);
    await pumpNarrow(tester, const DoubtBoardScreen(),
        [ChangeNotifierProvider<DoubtStore>.value(value: store)]);
    expect(find.textContaining('transitive dependency'), findsOneWidget);

    await tester.tap(find.textContaining('transitive dependency'));
    await tester.pumpAndSettle();
    expect(find.text('Mark as solved'), findsWidgets);
    expect(find.textContaining('AI · from your notes'), findsOneWidget);
  });

  for (final (label, ago, expected) in [
    ('lead', 2, 'Get ready'),
    ('answering', 9, 'Question 1 of 2'),
    ('reveal', 26, 'Scores so far'),
  ]) {
    testWidgets('a speed round fits: $label', (tester) async {
      final store =
          RoomStore(roomRepo: _SpeedRooms(ago: ago), quizPollInterval: null)
            ..debugUserId = 'me';
      await store.debugEnterRoomWithoutChannel(StudyRoom(
          id: 'r1',
          name: 'Room',
          inviteCode: 'ABC123',
          createdBy: 'host',
          createdAt: DateTime(2026, 10, 2)));
      await pumpNarrow(tester, const RoomQuizScreen(),
          [ChangeNotifierProvider<RoomStore>.value(value: store)]);
      expect(find.text(expected), findsOneWidget);
      // The round's 200 ms ticker goes with the screen.
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });
  }
}

class Utf8Length {
  const Utf8Length();
  int of(String s) => s.runes.fold(
      0,
      (n, r) =>
          n +
          (r < 0x80
              ? 1
              : r < 0x800
                  ? 2
                  : r < 0x10000
                      ? 3
                      : 4));
}

final _report = <String, dynamic>{
  'from': '2026-09-26',
  'to': '2026-10-02',
  'this_week': {
    'minutes': 145,
    'xp': 320,
    'tasks': 9,
    'active_days': 5,
    'quizzes': 2,
    'quiz_correct': 15,
    'quiz_total': 20,
    'group_quizzes': 1,
    'podiums': 1,
    'answers': 2,
    'answer_percent': 64,
  },
  'last_week': {'minutes': 90, 'xp': 200, 'tasks': 6, 'active_days': 3},
  'days': [
    // 26 Sep to 2 Oct; DateTime rolls 31 Sep over to 1 Oct.
    for (var i = 0; i < 7; i++)
      {
        'date': DateTime(2026, 9, 26 + i).toIso8601String().substring(0, 10),
        'minutes': i * 10,
        'xp': i * 5,
      },
  ],
  'units': [
    {
      'unit_label': 'Unit 2: Transactions, concurrency control and recovery',
      'answered': 8,
      'correct': 3,
      'answered_before': 4,
      'correct_before': 2,
    },
    {'unit_label': 'Unit 1: Normalisation', 'answered': 6, 'correct': 6},
  ],
  'streak': {'current': 4, 'best': 11},
  'mistakes_due': 6,
};

class _Game extends GamificationRepository {
  @override
  Future<WeeklyReport> getWeeklyReport() async => WeeklyReport.fromMap(_report);
}

class _Doubts extends DoubtRepository {
  _Doubts({this.noClass = false, bool seeded = false}) {
    if (seeded) {
      _thread = DoubtThread(
        id: 'd1',
        title:
            'Why does 3NF remove transitive dependency but BCNF goes further '
            'with every determinant?',
        body: 'I keep mixing them up in long answers.',
        subject: 'Database Management Systems',
        author: 'Aaryanandini Krishnamurthy-Venkataraman',
        initial: 'A',
        userId: 'me',
        isMine: true,
        createdAt: DateTime.now().subtract(const Duration(hours: 3)),
        answers: [
          DoubtAnswer(
            id: 'a1',
            body: 'In 3NF a non-key attribute may not depend on another '
                'non-key attribute. BCNF requires every determinant to be a '
                'candidate key, which also rules out a key attribute depending '
                'on a non-key one.',
            author: 'Aaryanandini Krishnamurthy-Venkataraman',
            initial: 'A',
            userId: 'me',
            isAi: true,
            createdAt: DateTime.now(),
          ),
          DoubtAnswer(
            id: 'a2',
            body: 'Think of BCNF as 3NF with no exceptions.',
            author: 'Ravi',
            initial: 'R',
            userId: 'ravi',
            votes: 3,
            createdAt: DateTime.now(),
          ),
        ],
      );
    }
  }

  final bool noClass;
  DoubtThread? _thread;

  List<DoubtSummary> get _list => _thread == null
      ? const []
      : [
          DoubtSummary(
            id: _thread!.id,
            title: _thread!.title,
            subject: _thread!.subject,
            author: _thread!.author,
            initial: _thread!.initial,
            createdAt: _thread!.createdAt,
            isMine: _thread!.isMine,
            solved: _thread!.solved,
            answers: _thread!.answers.length,
            hasAi: _thread!.hasAi,
          ),
        ];

  @override
  Future<List<DoubtSummary>> getDoubts({String filter = 'all'}) async {
    if (noClass) {
      throw 'Join your class first — the doubt board is shared with your '
          'classmates.';
    }
    return _list;
  }

  @override
  Future<DoubtThread> getDoubt(String id) async => _thread!;

  @override
  Future<DoubtThread> post({
    required String title,
    String? body,
    String? subject,
  }) async =>
      _thread = DoubtThread(
          id: 'd1',
          title: title,
          body: body,
          author: 'Me',
          initial: 'M',
          userId: 'me',
          isMine: true,
          createdAt: DateTime.now());

  @override
  Future<DoubtThread> answer(String doubtId, String body) async =>
      _thread = _copy(answers: [
        ..._thread!.answers,
        DoubtAnswer(
            id: 'a${_thread!.answers.length + 1}',
            body: body,
            author: 'Ravi',
            initial: 'R',
            userId: 'ravi',
            createdAt: DateTime.now()),
      ]);

  @override
  Future<DoubtThread> vote(String answerId) async => _thread = _copy(answers: [
        for (final a in _thread!.answers)
          a.id == answerId
              ? DoubtAnswer(
                  id: a.id,
                  body: a.body,
                  author: a.author,
                  initial: a.initial,
                  userId: a.userId,
                  createdAt: a.createdAt,
                  votes: a.votes + 1,
                  voted: true)
              : a,
      ]);

  @override
  Future<DoubtThread> markSolved(String doubtId, String? answerId) async =>
      _thread = _copy(solvedAnswerId: answerId);

  DoubtThread _copy({List<DoubtAnswer>? answers, String? solvedAnswerId}) {
    final t = _thread!;
    return DoubtThread(
      id: t.id,
      title: t.title,
      body: t.body,
      subject: t.subject,
      author: t.author,
      initial: t.initial,
      userId: t.userId,
      createdAt: t.createdAt,
      isMine: t.isMine,
      solvedAnswerId: solvedAnswerId ?? t.solvedAnswerId,
      answers: answers ?? t.answers,
    );
  }
}

/// A speed round that started [ago] seconds ago, two questions of 20 s.
class _SpeedRooms extends RoomRepository {
  _SpeedRooms({required this.ago});
  final int ago;

  RoomQuiz get _quiz {
    final now = DateTime.now().toUtc();
    final clock = SpeedClock.at(now, now.subtract(Duration(seconds: ago)), 20);
    final revealed = clock.revealing;
    return RoomQuiz.fromMap({
      'id': 'q1',
      'room_id': 'r1',
      'created_by': 'host',
      'title': 'Unit 2 — Transactions and concurrency control speed round',
      'question_count': 2,
      'status': 'running',
      'mode': 'speed',
      'seconds_per_question': 20,
      'started_at': now.subtract(Duration(seconds: ago)).toIso8601String(),
      'server_now': now.toIso8601String(),
      'players': [
        {
          'user_id': 'host',
          'full_name': 'Aaryanandini Krishnamurthy-Venkataraman',
          'score': revealed ? 912 : 0,
          'answered_current': true,
        },
        {'user_id': 'me', 'full_name': 'Yash', 'score': 0},
      ],
      'questions': clock.lead
          ? []
          : [
              {
                'id': 'a',
                'question': 'Which isolation level still allows phantom '
                    'reads but prevents non-repeatable reads?',
                'options': [
                  'Read uncommitted',
                  'Read committed',
                  'Repeatable read',
                  'Serializable',
                ],
                'correct_index': revealed ? 2 : null,
              },
            ],
      'my_picks': revealed ? {'a': 1} : null,
    });
  }

  @override
  Future<RoomQuiz?> getActiveQuiz(String roomId) async => _quiz;

  @override
  Future<RoomQuiz> getQuiz(String quizId) async => _quiz;

  @override
  Future<RoomQuiz> tickQuiz(String quizId) async => _quiz;
}
