import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'theme/app_theme.dart';
import 'widgets/common.dart';
import 'widgets/nav.dart';
import 'services/notification_service.dart';
import 'screens/home_screen.dart';
import 'screens/roadmap_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/flashcards_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/progress_screen.dart';
import 'screens/quiz_screen.dart';
import 'screens/pomodoro_screen.dart';
import 'screens/buddy_room_screen.dart';
import 'screens/achievements_screen.dart';
import 'screens/leaderboard_screen.dart';
import 'screens/rewards_screen.dart';

/// The main app shell — five bottom-nav tabs in an [IndexedStack] and a center
/// quick-actions button for the secondary screens.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  late final List<Widget> _tabs = [
    HomeScreen(onOpenProfile: () => setState(() => _tab = 4)),
    const RoadmapScreen(),
    const ChatScreen(),
    const QuizScreen(),
    const ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _initNotifications();
  }

  Future<void> _initNotifications() async {
    final ns = NotificationService();
    await ns.requestPermissions();
    // Schedule a daily reminder at 6:00 PM
    await ns.scheduleDailyReminder(
      id: 1,
      title: 'Time to study!',
      body: 'Keep your streak alive and hit your goals today.',
      hour: 18,
      minute: 0,
    );
  }

  void _open(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  void _showQuickActions() {
    final p = context.p;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      // Without this the sheet is capped at 9/16 of the screen, which is 14px
      // short of the five rows below. The scroll view then covers landscape and
      // large font scales, where even the full height isn't enough.
      isScrollControlled: true,
      builder: (sheetCtx) => Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(28),
          boxShadow: p.shadow,
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: p.line2, borderRadius: BorderRadius.circular(99)),
                ),
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Quick actions',
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 18,
                          fontWeight: FontWeight.w800)),
                ),
                const SizedBox(height: 16),
                _QuickAction(
                  icon: Symbols.style,
                  title: 'Flashcards',
                  subtitle: 'Review spaced-repetition decks',
                  color: p.primary,
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _open(FlashcardsScreen(onBack: () => Navigator.pop(context)));
                  },
                ),
                _QuickAction(
                  icon: Symbols.timer,
                  title: 'Focus session',
                  subtitle: 'Start a Pomodoro timer',
                  color: p.coral,
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _open(PomodoroScreen(onBack: () => Navigator.pop(context)));
                  },
                ),
                _QuickAction(
                  icon: Symbols.groups,
                  title: 'Study buddy room',
                  subtitle: 'Focus with your classmates',
                  color: p.green,
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _open(BuddyRoomScreen(onBack: () => Navigator.pop(context)));
                  },
                ),
                _QuickAction(
                  icon: Symbols.leaderboard,
                  title: 'Achievements',
                  subtitle: 'Streaks, badges & leaderboard',
                  color: p.amber,
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _open(
                        AchievementsScreen(onBack: () => Navigator.pop(context)));
                  },
                ),
                _QuickAction(
                  icon: Symbols.emoji_events,
                  title: 'Leaderboard & Leagues',
                  subtitle: 'Compete in weekly student leagues',
                  color: const Color(0xFFF59E0B),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _open(LeaderboardScreen(
                        onBack: () => Navigator.pop(context)));
                  },
                ),
                _QuickAction(
                  icon: Symbols.featured_seasonal_and_gifts,
                  title: 'My Rewards & Coupons',
                  subtitle: 'Streak freeze, XP perks & AI passes',
                  color: const Color(0xFF6366F1),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _open(RewardsScreen(
                        onBack: () => Navigator.pop(context)));
                  },
                ),
                _QuickAction(
                  icon: Symbols.insights,
                  title: 'Analytics',
                  subtitle: 'Study time, accuracy & consistency',
                  color: p.primary2,
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _open(const _ProgressPage());
                  },
                ),
              ],
            ),
          ),
        ),
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
            child: IndexedStack(index: _tab, children: _tabs),
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
          BottomNav(current: _tab, onTap: (i) => setState(() => _tab = i)),
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

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String title, subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            IconTile(icon,
                bg: color.withValues(alpha: 0.14), fg: color, size: 48),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(color: p.ink3, fontSize: 12.5)),
                ],
              ),
            ),
            Icon(Symbols.chevron_right, color: p.ink3, size: 22),
          ],
        ),
      ),
    );
  }
}
