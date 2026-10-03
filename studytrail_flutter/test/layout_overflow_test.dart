// Layout guard: the screens that showed "RIGHT OVERFLOWED BY … PIXELS" on a
// phone, rendered on a narrow 320-dp screen with deliberately long names.
// The test binding fails any test that ends with an overflow still reported,
// printing which widget overflowed and where — so there's nothing to assert
// beyond the screen having rendered.
//
// Text scale stays at 1.0 on purpose: flutter_test draws every glyph as a
// square one font-size wide, so its strings are already far wider than the
// app's real font — wider than a phone with its font size turned up.

import 'package:flutter/material.dart' hide MaterialType;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:studytrail_flutter/data/repositories.dart';
import 'package:studytrail_flutter/models/models.dart';
import 'package:studytrail_flutter/screens/answer_practice_screen.dart';
import 'package:studytrail_flutter/screens/chat_screen.dart';
import 'package:studytrail_flutter/screens/exam_papers_screen.dart';
import 'package:studytrail_flutter/screens/home_screen.dart';
import 'package:studytrail_flutter/screens/leaderboard_screen.dart';
import 'package:studytrail_flutter/screens/rewards_screen.dart';
import 'package:studytrail_flutter/state/stores.dart';
import 'package:studytrail_flutter/theme/app_theme.dart';
import 'package:studytrail_flutter/widgets/common.dart';
import 'package:studytrail_flutter/widgets/launch_splash.dart';
import 'package:studytrail_flutter/widgets/material_tile.dart';
import 'package:studytrail_flutter/widgets/playlist_tile.dart';
import 'package:studytrail_flutter/widgets/quick_actions_sheet.dart';

void _noop() {}

const _width = 320.0;
const _height = 900.0;

Future<void> _pumpNarrow(WidgetTester tester, Widget child,
    {List<ChangeNotifierProvider> providers = const []}) async {
  tester.view.physicalSize = const Size(_width * 3, _height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final app = MaterialApp(theme: AppTheme.light(), home: child);
  await tester.pumpWidget(
      providers.isEmpty ? app : MultiProvider(providers: providers, child: app));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('two buttons side by side never overflow', (tester) async {
    await _pumpNarrow(
      tester,
      Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            Row(children: [
              Expanded(child: PillButton('Upload a paper', icon: Icons.upload, onTap: () {})),
              const SizedBox(width: 10),
              Expanded(
                  child: PillButton('Snap a paper',
                      icon: Icons.photo_camera,
                      variant: PillVariant.outline,
                      onTap: () {})),
            ]),
            const SizedBox(height: 10),
            // The other shape: a compact button beside text that takes the rest.
            Row(children: [
              const Expanded(child: Text('Some explanation that wraps')),
              PillButton('Catch up', expand: false, onTap: () {}),
            ]),
          ]),
        ),
      ),
    );
    expect(find.text('Upload a paper'), findsOneWidget);
  });

  testWidgets('quick actions sheet fits', (tester) async {
    await _pumpNarrow(
      tester,
      Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: QuickActionsSheet(
            featured: const QuickAction(
                icon: Icons.timer,
                title: 'Start a focus session',
                subtitle: 'Pomodoro timer — focused minutes earn XP',
                color: Colors.deepOrange,
                onTap: _noop),
            sections: const [
              (
                'Practise',
                [
                  QuickAction(icon: Icons.style, title: 'Flashcards', color: Colors.indigo, onTap: _noop),
                  QuickAction(icon: Icons.edit_note, title: 'Answer practice', color: Colors.teal, onTap: _noop),
                  QuickAction(icon: Icons.history_edu, title: 'Past papers & mock', color: Colors.blue, onTap: _noop),
                ]
              ),
              (
                'Together',
                [
                  QuickAction(icon: Icons.groups, title: 'Study rooms', color: Colors.green, onTap: _noop),
                  QuickAction(icon: Icons.emoji_events, title: 'Class leaderboard', color: Colors.amber, onTap: _noop),
                ]
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Past papers & mock'), findsOneWidget);
  });

  testWidgets('Home with weak spots, a catch-up banner and dated subjects fits',
      (tester) async {
    await _pumpNarrow(
      tester,
      const Scaffold(body: HomeScreen()),
      providers: [
        ChangeNotifierProvider<HomeStore>(
            create: (_) => HomeStore(
                  profiles: const _Profiles(),
                  goals: _Goals(),
                  tasks: _Tasks(),
                  game: const _Game(),
                  roadmap: _Roadmap(),
                )),
        ChangeNotifierProvider<WeakSpotsStore>(
            create: (_) => WeakSpotsStore(quizzes: _Quizzes())),
      ],
    );
    expect(find.text('Catch up'), findsOneWidget);
    // Below the fold: the list only builds what's on screen, so scroll to it —
    // which also lays it out under the same narrow constraints.
    await tester.scrollUntilVisible(find.text('Weak spots'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Practice quiz'), findsOneWidget);
  });

  testWidgets('Past papers fits with topics and papers', (tester) async {
    await _pumpNarrow(
      tester,
      const ExamPapersScreen(),
      providers: [
        ChangeNotifierProvider<ExamPapersStore>(
            create: (_) => ExamPapersStore(papers: const _Papers())),
        ChangeNotifierProvider<QuizStore>(create: (_) => QuizStore()),
      ],
    );
    expect(find.text('Upload a paper'), findsOneWidget);
    expect(find.text('Take a mock exam'), findsOneWidget);
  });

  testWidgets('Answer practice fits with a question waiting', (tester) async {
    final store = AnswerPracticeStore(answers: _Answers())
      ..use(const PracticeQuestion(
          text: 'Explain the four isolation levels and the anomaly each one '
              'allows, with an example of a dirty read.',
          marks: 10,
          unitLabel: 'Unit 2: Transactions, concurrency control and recovery',
          paperQuestionId: 'pq-1'));
    await _pumpNarrow(
      tester,
      const AnswerPracticeScreen(),
      providers: [ChangeNotifierProvider<AnswerPracticeStore>.value(value: store)],
    );
    // The page's own list, not the answer box's scroller inside it.
    final page = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('Submit for grading'), 200,
        scrollable: page);
    expect(find.text('Submit for grading'), findsOneWidget);

    // Answering on paper instead: the photo panel fits too.
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('answer-mode-photo')), -200,
        scrollable: page);
    await tester.tap(find.byKey(const ValueKey('answer-mode-photo')));
    await tester.pumpAndSettle();
    expect(find.text('Take a photo'), findsOneWidget);
    expect(find.text('Grade my handwriting'), findsOneWidget);
  });

  testWidgets('Chat fits with follow-ups and a cited answer', (tester) async {
    final chat = ChatStore(chat: _Chat(), goals: const _NoGoal());
    await _pumpNarrow(
      tester,
      const Scaffold(body: ChatScreen()),
      providers: [
        ChangeNotifierProvider<ChatStore>.value(value: chat),
        ChangeNotifierProvider<OnboardingStore>(
            create: (_) => OnboardingStore(materials: const _NoMaterials())),
      ],
    );
    await chat.send('What is the difference between 3NF and BCNF?');
    await tester.pumpAndSettle();
    expect(find.text('Save as flashcards'), findsOneWidget);
  });

  testWidgets('a playlist row fits, paused and opened', (tester) async {
    const playlist = MaterialPlaylist(
      id: 'pl',
      youtubeId: 'PLUl4u3cNGP63EdVPNLG3ToM6LaEUuStEY',
      title: 'MIT 6.006 Introduction to Algorithms, Spring 2020 — full course',
      videoIds: ['a', 'b', 'c'],
    );
    const video = StudyMaterial(
      id: 'v1',
      sourceType: MaterialType.videoLink,
      title: '1. Algorithms and Computation — lecture with worked examples',
      storagePath: 'u/a.txt',
      externalUrl: 'https://www.youtube.com/watch?v=ZA-tUyM_y7s',
      status: IngestStatus.embedded,
      playlistId: 'pl',
    );
    await _pumpNarrow(
      tester,
      Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: PlaylistTile(
            playlist: playlist,
            progress: const PlaylistProgress(
                total: 92, ready: 34, failed: 2, skipped: 3, pending: 53),
            videos: const [video],
            onResume: () {},
            onRemove: () {},
            videoBuilder: (m) => MaterialTile(material: m, onRemove: () {}),
          ),
        ),
      ),
    );
    expect(find.text('Resume'), findsOneWidget);
    await tester.tap(find.text(playlist.title));
    await tester.pumpAndSettle();
    expect(find.text(video.title!), findsOneWidget);
  });

  testWidgets('the launch splash fits and settles with animations off',
      (tester) async {
    tester.view.physicalSize = const Size(_width * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: const LaunchSplash(),
    ));
    // The trail circles forever, so this pumps time rather than settling.
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text('Your study plan, one step at a time'), findsOneWidget);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const MediaQuery(
        data: MediaQueryData(disableAnimations: true, size: Size(_width, 640)),
        child: LaunchSplash(),
      ),
    ));
    // With animations off nothing is left running, so it does settle.
    await tester.pumpAndSettle();
  });

  testWidgets('Rewards fits', (tester) async {
    final game = GamificationStore(game: _Gamification(), profiles: const _Profiles());
    await _pumpNarrow(tester, const RewardsScreen(),
        providers: [ChangeNotifierProvider<GamificationStore>.value(value: game)]);
    expect(find.text('Streak Freeze'), findsOneWidget);
  });

  testWidgets('Leaderboard fits', (tester) async {
    final game = GamificationStore(game: _Gamification(), profiles: const _Profiles());
    await _pumpNarrow(tester, const LeaderboardScreen(),
        providers: [ChangeNotifierProvider<GamificationStore>.value(value: game)]);
    expect(find.text('Leaderboard'), findsOneWidget);
  });
}

// ── fakes ──────────────────────────────────────────────────────────────────

const _long = 'Practical 1 — EDA: Telecom customer churn with seaborn plots';

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
            name: 'Semester 5 end-semester examinations',
            examDate: DateTime.now().add(const Duration(days: 30))),
      ];
  @override
  Future<List<Subject>> getSubjects(String goalId) async => [
        Subject(
            id: 's1',
            name: 'Database Management Systems and Information Retrieval',
            examDate: DateTime.now().add(const Duration(days: 2))),
        const Subject(id: 's2', name: 'Machine Learning'),
      ];
}

class _Tasks extends TaskRepository {
  @override
  Future<List<DailyTask>> getTodayTasks() async => [
        DailyTask(
            id: 't1',
            title: 'Revise normalisation: 1NF, 2NF, 3NF and BCNF with examples',
            scheduledDate: DateTime.now()),
      ];
}

class _Game extends GamificationRepository {
  const _Game();
  @override
  Future<Streak> getStreak() async => const Streak(currentStreak: 12);
}

class _Roadmap extends RoadmapRepository {
  @override
  Future<RoadmapPace> getPace(String goalId) async => const RoadmapPace(
      hasRoadmap: true, total: 40, behind: 12, overdue: 3, perDay: 2, daysLeft: 30);
}

class _Quizzes extends QuizRepository {
  @override
  Future<List<WeakTopic>> getWeakTopics({int limit = 5}) async => const [
        WeakTopic(
            materialId: 'm',
            materialTitle: 'ml.pdf',
            unitLabel: _long,
            answered: 1,
            cardsReviewed: 3,
            cardsStruggling: 3,
            missRate: 1),
        WeakTopic(
            materialId: 'm',
            materialTitle: 'ml.pdf',
            unitLabel: 'Practical 3 — Logistic Regression on imbalanced data',
            answered: 2,
            cardsReviewed: 1,
            cardsStruggling: 1,
            missRate: 0.75),
      ];
}

class _Papers extends ExamPaperRepository {
  const _Papers();
  @override
  Future<List<ExamPaper>> getPapers() async => const [
        ExamPaper(
            id: 'p',
            title: 'DBMS winter examination 2024 question paper scan.pdf',
            year: 2024,
            status: 'analyzed',
            questionCount: 9,
            storagePath: 'u/paper_1.pdf'),
        ExamPaper(
            id: 'p2',
            title: 'Photo of 2023 paper.jpg',
            status: 'failed',
            error: "We couldn't find any questions in that file. Try a clearer copy.",
            storagePath: 'u/paper_2.jpg'),
      ];
  @override
  Future<List<ExamTopic>> getTopics() async => const [
        ExamTopic(
            unitLabel: 'Unit 2: Transactions, concurrency control and recovery',
            timesAsked: 6,
            totalMarks: 35,
            years: [2021, 2022, 2023, 2024]),
        ExamTopic(unitLabel: 'Unit 3: Indexing', timesAsked: 2, totalMarks: 15),
      ];
}

class _Answers extends AnswerRepository {
  @override
  Future<List<AnswerAttempt>> getAttempts({int limit = 20}) async => const [];
}

class _NoGoal extends GoalRepository {
  const _NoGoal();
  @override
  Future<Goal?> getActiveGoal() async => null;
}

class _Chat extends ChatRepository {
  bool _asked = false;
  @override
  Future<ChatThread> getOrCreateThread({String? goalId}) async =>
      const ChatThread(id: 't');
  @override
  Future<List<ChatMessage>> getMessages(String threadId) async => !_asked
      ? const []
      : [
          const ChatMessage(
              id: 'q', role: ChatRole.user, text: 'What is the difference between 3NF and BCNF?'),
          const ChatMessage(
            id: 'a',
            role: ChatRole.ai,
            text: 'BCNF is stricter: for every dependency X -> Y, X must be a '
                'superkey [1]. 3NF allows Y to be part of a candidate key.',
            citations: [
              ChatCitation(id: 'c', unitLabel: 'Unit 1: Normalisation and functional dependencies'),
            ],
          ),
        ];
  @override
  Future<({String answer, List<String> suggestions})> askAi({
    required String threadId,
    required String question,
    String? subjectId,
  }) async {
    _asked = true;
    return (
      answer: '',
      suggestions: const [
        'What is a transitive dependency?',
        'When does a 3NF table fail BCNF in practice?',
        'How do you decompose into BCNF without losing dependencies?',
      ],
    );
  }
}

class _Gamification extends GamificationRepository {
  @override
  Future<List<String>> evaluateBadges() async => const [];
  @override
  Future<Streak> getStreak() async => const Streak(currentStreak: 12, bestStreak: 30);
  @override
  Future<List<AchievementBadge>> getBadges({bool onlyUnlocked = false}) async =>
      GamificationRepository.defaultBadges;
  @override
  Future<List<ActivityDay>> getRecentActivity({int days = 60}) async => const [];
  @override
  Future<List<LeaderboardEntry>> getLeaderboard({int limit = 20}) async => const [
        LeaderboardEntry(
            userId: 'a',
            fullName: 'Aaryanandini Krishnamurthy-Venkataraman',
            level: 12,
            totalXp: 128450,
            goldenBorder: true,
            rank: 1),
        LeaderboardEntry(
            userId: 'b', fullName: 'Yash', level: 3, totalXp: 950, isMe: true, rank: 2),
        LeaderboardEntry(
            userId: 'c', fullName: 'Ravi', level: 2, totalXp: 600, rank: 3),
      ];
  @override
  Future<RewardWallet> getRewardWallet() async => const RewardWallet(
        earned: 12000,
        spent: 300,
        balance: 11700,
        rewards: [
          RewardItem(
              key: 'streak_freeze',
              title: 'Streak Freeze',
              description: 'Covers one missed day so your streak survives.',
              costXp: 100,
              maxHeld: 2,
              held: 2,
              used: 3),
          RewardItem(
              key: 'golden_border',
              title: 'Golden Scholar Border',
              description: 'A gold ring around your name on the leaderboard.',
              costXp: 300,
              maxHeld: 1),
        ],
      );
}

class _NoMaterials extends MaterialRepository {
  const _NoMaterials();
  @override
  Future<List<StudyMaterial>> getMaterials({String? goalId}) async => const [];
  @override
  Future<List<MaterialPlaylist>> getPlaylists() async => const [];
}
