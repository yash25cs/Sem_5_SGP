import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/stores.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/badge_style.dart';
import '../theme/theme_controller.dart';
import '../widgets/common.dart';
import '../widgets/data_states.dart';
import '../widgets/streak_heatmap.dart';
import 'achievements_screen.dart';
import 'settings_screen.dart';

/// Profile tab — identity card, XP/level, stats, achievements, and settings.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ProfileStore>().load();
      context.read<GamificationStore>().load();
      context.read<ProgressStore>().load();
    });
  }

  Future<void> _refresh() async {
    await Future.wait([
      context.read<ProfileStore>().load(),
      context.read<GamificationStore>().load(),
      context.read<ProgressStore>().load(),
    ]);
  }

  /// Flavour title next to the level number — cosmetic, derived from level.
  String _levelTitle(int level) => switch (level) {
        <= 2 => 'Beginner',
        <= 4 => 'Learner',
        <= 6 => 'Achiever',
        <= 9 => 'Scholar',
        <= 14 => 'Expert',
        _ => 'Master',
      };

  /// 1240 → "1,240".
  String _thousands(int n) =>
      n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

  Future<void> _confirmLogout() async {
    final p = context.p;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: p.card,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Log out?',
            style: TextStyle(
                color: p.ink, fontSize: 18, fontWeight: FontWeight.w800)),
        content: Text('Your progress stays saved to your account.',
            style: TextStyle(color: p.ink2, fontSize: 14, height: 1.45)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Cancel', style: TextStyle(color: p.ink3)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Log out',
                style: TextStyle(
                    color: p.error, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
    await context.read<AuthStore>().signOut();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final theme = context.watch<ThemeController>();
    final store = context.watch<ProfileStore>();
    final game = context.watch<GamificationStore>();

    final profile = store.profile;
    final goal = store.activeGoal;
    final rank = game.myRank;

    // Unlocked badges lead the strip so the earned ones are what you see first.
    final badges = [
      ...game.badges.where((b) => b.unlocked),
      ...game.badges.where((b) => !b.unlocked),
    ].take(8).toList();

    return RefreshIndicator(
      color: p.primary,
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
        children: [
          Row(
            children: [
              Text('Profile',
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6)),
              const Spacer(),
              RoundIconButton(Symbols.settings,
                  plain: false,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => SettingsScreen(
                          onBack: () => Navigator.pop(context))))),
            ],
          ),
          const SizedBox(height: 16),

          if (store.error != null)
            ErrorNotice(
              message: store.error!,
              onRetry: () => context.read<ProfileStore>().load(),
            ),

          if (profile == null)
            const LoadingBlock(height: 190)
          else
            _IdentityCard(
              profile: profile,
              title: _levelTitle(profile.level),
              xpLabel: '${_thousands(profile.xp)} XP',
            ),
          const SizedBox(height: 18),

          // quick stats
          Row(
            children: [
              Expanded(
                  child: _MiniStat('${game.streak.currentStreak}', 'Day streak',
                      Symbols.local_fire_department, p.coral)),
              const SizedBox(width: 12),
              Expanded(
                  child: _MiniStat(
                      goal == null ? '—' : '${goal.overallPercent.round()}%',
                      'Roadmap done',
                      Symbols.task_alt,
                      p.green)),
              const SizedBox(width: 12),
              Expanded(
                  child: _MiniStat(rank == null ? '—' : '#${rank.rank}',
                      'Class rank', Symbols.leaderboard, p.primary)),
            ],
          ),
          const SizedBox(height: 22),

          // achievements
          CardHeader('Achievements',
              action: InkWell(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => AchievementsScreen(
                        onBack: () => Navigator.pop(context)))),
                child: Text('See all',
                    style: TextStyle(
                        color: p.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w800)),
              )),
          if (game.loading && !game.loaded && badges.isEmpty)
            const LoadingBlock(height: 120)
          else if (badges.isEmpty)
            EmptyState(
              icon: Symbols.workspace_premium,
              title: 'No badges yet',
              message: 'Study, review cards, and finish quizzes to earn them.',
            )
          else
            SizedBox(
              // 14 + 48 icon + 8 + two label lines + 14 of padding = 110.4, so
              // the old 108 overflowed by ~2px — the yellow stripe reported
              // across the middle of this screen.
              height: 120,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.zero,
                children: [
                  for (final b in badges)
                    InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => AchievementsScreen(
                              onBack: () => Navigator.pop(context)))),
                      child: _Badge(badge: b),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 22),

          // study consistency heatmap
          CardHeader('Consistency'),
          Builder(builder: (context) {
            final progress = context.watch<ProgressStore>();
            if (progress.loading && !progress.loaded) {
              return const LoadingBlock(height: 120);
            }
            return AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StreakHeatmap(progress.heatmap, weeks: 12),
                  const SizedBox(height: 14),
                  const HeatmapLegend(),
                ],
              ),
            );
          }),
          const SizedBox(height: 22),

          // settings list
          CardHeader('Settings'),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                _SettingRow(Symbols.dark_mode, 'Dark mode', p.primary,
                    trailing: Switch(
                      value: theme.isDark,
                      onChanged: (v) => context.read<ThemeController>().set(v),
                    )),
                _divider(p),
                _SettingRow(Symbols.target, 'Edit study goal', p.green,
                    trailing: _chevron(p),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => SettingsScreen(
                            onBack: () => Navigator.pop(context))))),
                _divider(p),
                _SettingRow(Symbols.notifications, 'Study reminders', p.coral,
                    trailing: _chevron(p),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => SettingsScreen(
                            onBack: () => Navigator.pop(context))))),
                _divider(p),
                _SettingRow(Symbols.help, 'Help & feedback', p.amber,
                    trailing: _chevron(p),
                    onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content:
                                  Text('Reach out at yash@charusat.edu.in')),
                        )),
              ],
            ),
          ),
          const SizedBox(height: 16),
          PillButton('Log out',
              icon: Symbols.logout,
              variant: PillVariant.danger,
              onTap: context.watch<AuthStore>().busy ? null : _confirmLogout),
          const SizedBox(height: 12),
          Center(
            child: Text('StudyTrail v1.0 · Made for SGP',
                style: TextStyle(color: p.ink3, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _divider(AppPalette p) =>
      Divider(color: p.line, height: 1, indent: 60, endIndent: 16);
  Widget _chevron(AppPalette p) =>
      Icon(Symbols.chevron_right, color: p.ink3, size: 22);
}

/// Gradient hero card: avatar, name, enrollment line, level chip, XP bar.
class _IdentityCard extends StatelessWidget {
  const _IdentityCard({
    required this.profile,
    required this.title,
    required this.xpLabel,
  });

  final Profile profile;
  final String title;
  final String xpLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.p;

    // "D25CS118 · CE, CSPIT" — but any of those three can be unset.
    final course =
        [profile.branch, profile.college].where((s) => (s ?? '').isNotEmpty);
    final subtitle = [
      if ((profile.enrollmentId ?? '').isNotEmpty) profile.enrollmentId!,
      if (course.isNotEmpty) course.join(', '),
    ].join(' · ');

    final remaining = profile.xpToNext - (profile.xp % profile.xpToNext);

    return AppCard(
      gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [p.primary, p.primary2]),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.5), width: 2)),
                child: GradAvatar(profile.initial,
                    size: 64,
                    colors: const [Color(0xFFFFC773), Color(0xFFFE6F42)]),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        profile.fullName.isEmpty
                            ? 'Your profile'
                            : profile.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(
                        subtitle.isEmpty
                            ? 'Add your details in Settings'
                            : subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 13)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(999)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Symbols.workspace_premium,
                            color: Color(0xFFFFC773), size: 16, fill: 1),
                        const SizedBox(width: 5),
                        Text('Level ${profile.level} · $title',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w800)),
                      ]),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // XP to next level
          Row(children: [
            Text(xpLabel,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800)),
            const Spacer(),
            Text('$remaining XP to Level ${profile.level + 1}',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOut,
              tween: Tween(begin: 0, end: profile.levelProgress),
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 9,
                backgroundColor: Colors.white.withValues(alpha: 0.22),
                valueColor: const AlwaysStoppedAnimation(Color(0xFFFFC773)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat(this.value, this.label, this.icon, this.color);
  final String value, label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(18),
        boxShadow: p.shadowSm,
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24, fill: 1),
          const SizedBox(height: 8),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: p.ink, fontSize: 18, fontWeight: FontWeight.w800)),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(color: p.ink3, fontSize: 11)),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.badge});

  final AchievementBadge badge;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final style = BadgeStyle.of(context, badge);
    final unlocked = badge.unlocked;

    return Tooltip(
      message: badge.description ?? badge.name,
      child: Container(
        width: 92,
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(18),
          boxShadow: p.shadowSm,
        ),
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: unlocked
                    ? style.color.withValues(alpha: 0.15)
                    : p.card2,
              ),
              child: Icon(unlocked ? style.icon : Symbols.lock,
                  color: unlocked ? style.color : p.line2,
                  size: 24,
                  fill: unlocked ? 1 : 0),
            ),
            const SizedBox(height: 8),
            // Flexible, not a bare Text: the strip has a fixed height, so at a
            // large system font scale the label has to give way rather than
            // overflow the card.
            Flexible(
              child: Text(badge.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: unlocked ? p.ink2 : p.ink3,
                      fontSize: 11,
                      height: 1.2,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow(this.icon, this.label, this.color,
      {required this.trailing, this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            IconTile(icon,
                bg: color.withValues(alpha: 0.14),
                fg: color,
                size: 34,
                radius: 11),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700)),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}
