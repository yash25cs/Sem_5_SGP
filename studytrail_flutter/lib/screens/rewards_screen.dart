import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/stores.dart';
import '../theme/app_theme.dart';
import '../widgets/data_states.dart';

/// The XP rewards store.
///
/// Balance, catalog and purchases all live on the server (`0012_rewards_store`):
/// the earlier version kept spent XP in SharedPreferences, so it was per phone
/// rather than per student and nothing it sold did anything. Every item here
/// has an effect the server enforces.
class RewardsScreen extends StatefulWidget {
  const RewardsScreen({super.key, this.onBack});
  final VoidCallback? onBack;

  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<GamificationStore>().loadWallet();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _handleRedeem(RewardItem item, int balance) async {
    final p = context.p;
    final style = _RewardStyle.of(item.key);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: p.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Icon(style.icon, color: style.color, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Redeem reward?',
                style: TextStyle(
                  color: p.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Spend ${item.costXp} XP on "${item.title}"?',
              style: TextStyle(
                color: p.ink,
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'You\'ll have ${balance - item.costXp} XP left to spend. Your '
              'level and leaderboard rank don\'t change.',
              style: TextStyle(color: p.ink2, fontSize: 13, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(color: p.ink3, fontWeight: FontWeight.w700),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: p.primary,
              foregroundColor: p.onPrimary,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'Redeem (${item.costXp} XP)',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final store = context.read<GamificationStore>();
    final ok = await store.redeem(item.key);
    if (!mounted) return;
    if (ok) HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? '🎉 ${item.title} is yours!'
              : store.error ?? 'Could not redeem that. Try again.',
        ),
        backgroundColor: ok ? p.green : p.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final store = context.watch<GamificationStore>();
    final wallet = store.wallet;

    final headerBg = isDark ? p.card : const Color(0xFFFFF9E6);

    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: headerBg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Symbols.arrow_back_ios_new, size: 20, color: p.ink),
          onPressed: () {
            if (widget.onBack != null) {
              widget.onBack!();
            } else {
              Navigator.of(context).maybePop();
            }
          },
        ),
      ),
      body: Column(
        children: [
          // Header with balance and trophy
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            decoration: BoxDecoration(
              color: headerBg,
              border: Border(bottom: BorderSide(color: p.line)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Spend your XP in',
                        style: TextStyle(
                          color: p.ink2,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'My Rewards',
                        style: TextStyle(
                          color: p.ink,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: p.card,
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                            color: isDark ? p.line : const Color(0xFFFFD54F),
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Symbols.diamond,
                              size: 15,
                              color: Color(0xFFF59E0B),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                wallet == null
                                    ? '… XP available'
                                    : '${wallet.balance} XP available',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color:
                                      isDark ? p.amber : const Color(0xFF78350F),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (wallet != null && wallet.spent > 0) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${wallet.earned} earned · ${wallet.spent} spent',
                          style: TextStyle(color: p.ink3, fontSize: 11.5),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: isDark ? p.card2 : const Color(0xFFFFF3C4),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFFCA28).withValues(alpha: 0.25),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Symbols.emoji_events,
                      color: Color(0xFFF59E0B),
                      size: 48,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Container(
            color: p.card,
            child: TabBar(
              controller: _tabController,
              indicatorColor: p.primary,
              indicatorWeight: 3,
              labelColor: p.primary,
              unselectedLabelColor: p.ink2,
              labelStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              tabs: const [
                Tab(text: 'Store'),
                Tab(text: 'How it works'),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: p.line),

          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _StoreTab(
                  wallet: wallet,
                  error: store.error,
                  busy: store.busy,
                  onRetry: store.loadWallet,
                  onRedeem: (item) => _handleRedeem(item, wallet?.balance ?? 0),
                ),
                const _HowItWorksTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Icon and colour per catalog key. Unknown keys (added server-side later)
/// still render, with a generic gift.
class _RewardStyle {
  const _RewardStyle(this.icon, this.color);
  final IconData icon;
  final Color color;

  static _RewardStyle of(String key) => switch (key) {
        'streak_freeze' =>
          const _RewardStyle(Symbols.ac_unit, Color(0xFF0284C7)),
        'golden_border' => const _RewardStyle(
            Symbols.military_tech,
            Color(0xFFEAB308),
          ),
        _ => const _RewardStyle(Symbols.redeem, Color(0xFF8B5CF6)),
      };
}

class _StoreTab extends StatelessWidget {
  const _StoreTab({
    required this.wallet,
    required this.error,
    required this.busy,
    required this.onRetry,
    required this.onRedeem,
  });

  final RewardWallet? wallet;
  final String? error;
  final bool busy;
  final VoidCallback onRetry;
  final ValueChanged<RewardItem> onRedeem;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final w = wallet;

    return RefreshIndicator(
      color: p.primary,
      onRefresh: () async => onRetry(),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (error != null && !busy) ...[
            ErrorNotice(message: error!, onRetry: onRetry),
            const SizedBox(height: 14),
          ],
          if (w == null && error == null)
            const LoadingBlock(height: 160)
          else if (w != null) ...[
            Text(
              'Available rewards',
              style: TextStyle(
                color: p.ink,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 14),
            for (final item in w.rewards)
              _RewardTile(
                item: item,
                balance: w.balance,
                busy: busy,
                onRedeem: () => onRedeem(item),
              ),
          ],
        ],
      ),
    );
  }
}

class _RewardTile extends StatelessWidget {
  const _RewardTile({
    required this.item,
    required this.balance,
    required this.busy,
    required this.onRedeem,
  });

  final RewardItem item;
  final int balance;
  final bool busy;
  final VoidCallback onRedeem;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final style = _RewardStyle.of(item.key);
    final owned = item.held > 0;
    final canAfford = balance >= item.costXp;
    final permanent = item.maxHeld == 1;

    final String label;
    if (item.atCap) {
      label = permanent ? 'Owned' : 'Holding the max';
    } else if (!canAfford) {
      label = 'Need ${item.costXp - balance} more XP';
    } else {
      label = 'Redeem';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: owned ? p.green : p.line,
          width: owned ? 1.5 : 1,
        ),
        boxShadow: p.shadowSm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: style.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(style.icon, color: style.color, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        style: TextStyle(
                          color: p.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: p.amberSoft.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${item.costXp} XP',
                        style: TextStyle(
                          color: p.onAmber,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  item.description,
                  style: TextStyle(color: p.ink2, fontSize: 12.5, height: 1.35),
                ),
                if (owned || item.used > 0) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Symbols.verified, size: 15, color: p.green),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          permanent
                              ? 'Active on your profile'
                              : [
                                  if (owned) 'You have ${item.held}',
                                  if (item.used > 0) '${item.used} used so far',
                                ].join(' · '),
                          style: TextStyle(
                            color: p.green,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: label == 'Redeem' && !busy ? onRedeem : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: p.primary,
                    foregroundColor: p.onPrimary,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HowItWorksTab extends StatelessWidget {
  const _HowItWorksTab();

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final questions = [
      (
        q: 'How do I earn XP?',
        a: 'Tick off daily tasks (15 XP each), finish Pomodoro focus blocks '
            '(1 XP per focused minute), review flashcards that are due (2 XP '
            'each) and answer quiz questions correctly (up to 10 XP each). '
            'The server works out every award, so XP can\'t be edited in.',
      ),
      (
        q: 'Does spending XP lower my level or rank?',
        a: 'No. Your level and your place on the class leaderboard use all '
            'the XP you have ever earned. Spending only lowers the balance '
            'shown on this screen.',
      ),
      (
        q: 'How does a Streak Freeze work?',
        a: 'If you miss a day, the next time you study a freeze is used up '
            'automatically and your streak carries on instead of restarting. '
            'You can hold two, which covers a gap of up to two days.',
      ),
      (
        q: 'Where does the Golden Scholar Border show?',
        a: 'Around your name on the class leaderboard, for you and your '
            'classmates to see. It\'s permanent.',
      ),
      (
        q: 'Can I hide from the leaderboard?',
        a: 'Yes — leave your class from the Study Rooms screen. Your XP, '
            'streak and badges stay; you just stop appearing in the ranking.',
      ),
    ];

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'How it works',
          style: TextStyle(
            color: p.ink,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 14),
        for (final item in questions)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: p.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: p.line),
            ),
            child: ExpansionTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              collapsedShape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Text(
                item.q,
                style: TextStyle(
                  color: p.ink,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              iconColor: p.ink,
              collapsedIconColor: p.ink2,
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                Text(
                  item.a,
                  style: TextStyle(color: p.ink2, fontSize: 13, height: 1.45),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
