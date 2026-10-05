import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import 'models/models.dart';
import 'theme/app_theme.dart';
import 'widgets/common.dart';
import 'widgets/lazy_indexed_stack.dart';
import 'widgets/nav.dart';
import 'widgets/quick_actions_sheet.dart';
import 'state/reminder_sync.dart';
import 'state/stores.dart';
import 'screens/home_screen.dart';
import 'screens/roadmap_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/flashcards_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/progress_screen.dart';
import 'screens/quiz_screen.dart';
import 'screens/pomodoro_screen.dart';
import 'screens/buddy_room_screen.dart';
import 'screens/doubt_board_screen.dart';
import 'screens/exam_papers_screen.dart';
import 'screens/achievements_screen.dart';
import 'screens/answer_practice_screen.dart';
import 'screens/leaderboard_screen.dart';
import 'screens/rewards_screen.dart';
import 'screens/weekly_report_screen.dart';
import 'services/home_widget_sync.dart';
import 'services/notification_service.dart';

/// The main app shell — five bottom-nav tabs in an [IndexedStack] and a center
/// quick-actions button for the secondary screens.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  void _selectTab(int tab) => setState(() => _tab = tab);

  late final List<Widget> _tabs = [
    HomeScreen(
      onOpenProfile: () => _selectTab(4),
      onOpenQuiz: () => _selectTab(3),
    ),
    const RoadmapScreen(),
    const ChatScreen(),
    const QuizScreen(),
    const ProfileScreen(),
  ];

  late final AppLifecycleListener _lifecycle;
  StreamSubscription<WidgetTarget>? _widgetTaps;

  @override
  void initState() {
    super.initState();
    // Once per launch it may ask for the notification permission; the
    // lifecycle re-syncs never do, or a denied dialog would reappear on every
    // resume.
    ReminderSync.run(askPermission: true);
    _lifecycle = AppLifecycleListener(
      onResume: () {
        ReminderSync.run();
        _resumeImports();
      },
      // Leaving the app is when today's studying is known, so a 6 PM nudge
      // for work already done gets dropped.
      onPause: ReminderSync.run,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _resumeImports());
    // A tapped weekly-report notification, now or the one that launched us.
    NotificationService().opened.addListener(_onNotificationOpened);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onNotificationOpened());
    // A home-screen widget tapped while the app runs, or the one that
    // launched it.
    _widgetTaps = HomeWidgetSync.taps.listen(_openFromWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final target = await HomeWidgetSync.takeLaunchTarget();
      if (target != null) _openFromWidget(target);
    });
  }

  /// A playlist the phone didn't finish reading carries on (D-038) — at launch
  /// and whenever the app comes back to the front, since the phone is what
  /// fetches the captions and Android may have paused it mid-way.
  void _resumeImports() {
    if (!mounted) return;
    context.read<OnboardingStore>().resumeImports();
  }

  @override
  void dispose() {
    NotificationService().opened.removeListener(_onNotificationOpened);
    _widgetTaps?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  /// Takes a widget tap to its screen: Focus, Cards, Ask AI and the streak
  /// open theirs; the countdown opens the Roadmap. Whatever was open on top
  /// is closed first, so a tap always lands where it says.
  void _openFromWidget(WidgetTarget target) {
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    switch (target) {
      case WidgetTarget.home:
        _selectTab(0);
      case WidgetTarget.roadmap:
        _selectTab(1);
      case WidgetTarget.chat:
        _selectTab(2);
      case WidgetTarget.focus:
        _open(PomodoroScreen(onBack: () => Navigator.pop(context)));
      case WidgetTarget.flashcards:
        _open(FlashcardsScreen(onBack: () => Navigator.pop(context)));
      case WidgetTarget.achievements:
        _open(AchievementsScreen(onBack: () => Navigator.pop(context)));
    }
  }

  void _onNotificationOpened() {
    final opened = NotificationService().opened;
    if (!mounted || opened.value != NotificationService.weeklyReportPayload) {
      return;
    }
    opened.value = null;
    _open(WeeklyReportScreen(onBack: () => Navigator.pop(context)));
  }

  void _open(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  void _showQuickActions() {
    final p = context.p;
    // Each action closes the sheet first, then opens its screen.
    VoidCallback go(BuildContext sheetCtx, Widget Function() screen) => () {
          Navigator.pop(sheetCtx);
          _open(screen());
        };

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      // Lets the sheet grow past 9/16 of the screen at large font scales; the
      // sheet scrolls inside itself when even that isn't enough.
      isScrollControlled: true,
      builder: (sheetCtx) => QuickActionsSheet(
        featured: QuickAction(
          icon: Symbols.timer,
          title: 'Start a focus session',
          subtitle: 'Pomodoro timer — focused minutes earn XP',
          color: p.coral,
          onTap: go(sheetCtx,
              () => PomodoroScreen(onBack: () => Navigator.pop(context))),
        ),
        sections: [
          (
            'Practise',
            [
              QuickAction(
                icon: Symbols.style,
                title: 'Flashcards',
                color: p.primary,
                onTap: go(sheetCtx,
                    () => FlashcardsScreen(onBack: () => Navigator.pop(context))),
              ),
              QuickAction(
                icon: Symbols.edit_note,
                title: 'Answer practice',
                color: const Color(0xFF14B8A6),
                onTap: go(
                    sheetCtx,
                    () => AnswerPracticeScreen(
                        onBack: () => Navigator.pop(context))),
              ),
              QuickAction(
                icon: Symbols.history_edu,
                title: 'Past papers & mock',
                color: const Color(0xFF0EA5E9),
                onTap: go(
                  sheetCtx,
                  () => ExamPapersScreen(
                    onBack: () => Navigator.pop(context),
                    onOpenQuiz: () {
                      Navigator.pop(context);
                      _selectTab(3);
                    },
                    onPractice: (q) => _open(AnswerPracticeScreen(
                      onBack: () => Navigator.pop(context),
                      initial: PracticeQuestion(
                        text: q.text,
                        marks: q.marks ?? 5,
                        unitLabel: q.unitLabel,
                        paperQuestionId: q.id,
                      ),
                    )),
                  ),
                ),
              ),
            ],
          ),
          (
            'Together',
            [
              QuickAction(
                icon: Symbols.groups,
                title: 'Study rooms',
                color: p.green,
                onTap: go(sheetCtx,
                    () => BuddyRoomScreen(onBack: () => Navigator.pop(context))),
              ),
              QuickAction(
                icon: Symbols.forum,
                title: 'Doubt board',
                color: const Color(0xFF8B5CF6),
                onTap: go(
                    sheetCtx,
                    () => DoubtBoardScreen(
                        onBack: () => Navigator.pop(context))),
              ),
              QuickAction(
                icon: Symbols.emoji_events,
                title: 'Class leaderboard',
                color: const Color(0xFFF59E0B),
                onTap: go(
                    sheetCtx,
                    () => LeaderboardScreen(
                        onBack: () => Navigator.pop(context))),
              ),
            ],
          ),
          (
            'Progress',
            [
              QuickAction(
                icon: Symbols.calendar_view_week,
                title: 'Weekly report',
                color: p.coral,
                onTap: go(
                    sheetCtx,
                    () => WeeklyReportScreen(
                        onBack: () => Navigator.pop(context))),
              ),
              QuickAction(
                icon: Symbols.military_tech,
                title: 'Achievements',
                color: p.amber,
                onTap: go(
                    sheetCtx,
                    () => AchievementsScreen(
                        onBack: () => Navigator.pop(context))),
              ),
              QuickAction(
                icon: Symbols.insights,
                title: 'Analytics',
                color: p.primary2,
                onTap: go(sheetCtx, () => const _ProgressPage()),
              ),
              QuickAction(
                icon: Symbols.featured_seasonal_and_gifts,
                title: 'My rewards',
                color: const Color(0xFF6366F1),
                onTap: go(sheetCtx,
                    () => RewardsScreen(onBack: () => Navigator.pop(context))),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Scaffold(
      backgroundColor: p.bg,
      body: Column(
        children: [
          const TopInset(),
          Expanded(
            // Each tab is built, and loads its data, when first opened.
            child: LazyIndexedStack(index: _tab, children: _tabs),
          ),
        ],
      ),
      floatingActionButton: _tab == 2
          ? null
          : FloatingActionButton(
              onPressed: _showQuickActions,
              backgroundColor: p.coral,
              elevation: 0,
              shape: const CircleBorder(),
              child: Icon(Symbols.bolt, color: Colors.white, size: 28, fill: 1),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar:
          BottomNav(current: _tab, onTap: _selectTab),
    );
  }
}

/// Wraps [ProgressScreen] with its own scaffold + back button for pushing.
class _ProgressPage extends StatelessWidget {
  const _ProgressPage();
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Scaffold(
      backgroundColor: p.bg,
      body: Column(
        children: [
          const TopInset(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 20, 6),
            child: Row(
              children: [
                RoundIconButton(Symbols.arrow_back,
                    onTap: () => Navigator.pop(context)),
                const SizedBox(width: 8),
                Text('Analytics',
                    style: TextStyle(
                        color: p.ink, fontSize: 20, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          const Expanded(child: ProgressScreen()),
        ],
      ),
    );
  }
}
