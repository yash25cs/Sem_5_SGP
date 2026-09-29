import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../data/local_prefs.dart';
import '../state/stores.dart';
import '../theme/app_theme.dart';

/// My Rewards Screen with persistent unlocks, XP deduction, copy button, and expiry dates.
class RewardsScreen extends StatefulWidget {
  const RewardsScreen({super.key, this.onBack});
  final VoidCallback? onBack;

  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _spentXp = 0;

  final List<_CouponReward> _coupons = [
    _CouponReward(
      id: 'streak-freeze-1',
      title: 'Streak Freeze Shield',
      description: 'Protects your streak if you miss a study day.',
      costXp: 100,
      code: 'FREEZE-ST-2026',
      expiryDate: 'Expires 31 Dec 2026',
      icon: Symbols.shield,
      color: const Color(0xFF0284C7),
    ),
    _CouponReward(
      id: 'xp-booster-1',
      title: '2x XP Power Boost',
      description: 'Earn double XP on your next 3 quiz and flashcard reviews.',
      costXp: 150,
      code: 'BOOST-2X-XP',
      expiryDate: 'Valid for 30 days',
      icon: Symbols.bolt,
      color: const Color(0xFFF59E0B),
    ),
    _CouponReward(
      id: 'ai-quiz-pass-1',
      title: 'Pro AI Practice Exam',
      description: 'Generate an extensive 15-question multi-topic practice test.',
      costXp: 200,
      code: 'AI-PRO-EXAM',
      expiryDate: 'Expires 15 Nov 2026',
      icon: Symbols.psychology,
      color: const Color(0xFF8B5CF6),
    ),
    _CouponReward(
      id: 'golden-badge-1',
      title: 'Golden Scholar Border',
      description: 'Exclusive shiny aura for your avatar on the Leaderboard.',
      costXp: 300,
      code: 'GOLD-SCHOLAR',
      expiryDate: 'Permanent Perk',
      icon: Symbols.military_tech,
      color: const Color(0xFFEAB308),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final unlocked = await LocalPrefs.getUnlockedRewards();
    final spent = await LocalPrefs.getSpentRewardXp();
    if (!mounted) return;
    setState(() {
      _spentXp = spent;
      for (final coupon in _coupons) {
        if (unlocked.contains(coupon.id)) {
          coupon.isUnlocked = true;
        }
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _handleRedeem(_CouponReward coupon, int availableXp) async {
    final p = context.p;
    if (availableXp < coupon.costXp) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('You need ${coupon.costXp - availableXp} more XP to redeem this reward!'),
          backgroundColor: p.error,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: p.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Icon(coupon.icon, color: coupon.color, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Redeem Reward?',
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
              'Redeem "${coupon.title}" for ${coupon.costXp} XP?',
              style: TextStyle(color: p.ink, fontSize: 14.5, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'This will unlock your redemption code and activate the perk on your account.',
              style: TextStyle(color: p.ink2, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: p.card2,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Symbols.schedule, size: 16, color: p.ink3),
                  const SizedBox(width: 8),
                  Text(
                    coupon.expiryDate,
                    style: TextStyle(color: p.ink2, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text('Cancel', style: TextStyle(color: p.ink3, fontWeight: FontWeight.w700)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: p.primary,
              foregroundColor: p.onPrimary,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Redeem (${coupon.costXp} XP)', style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await LocalPrefs.saveUnlockedReward(coupon.id, coupon.costXp);
    HapticFeedback.mediumImpact();

    setState(() {
      coupon.isUnlocked = true;
      _spentXp += coupon.costXp;
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🎉 Successfully unlocked ${coupon.title}!'),
        backgroundColor: p.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final profile = context.watch<ProfileStore>().profile;
    final baseProfileXp = profile?.xp ?? 262;
    final availableXp = (baseProfileXp - _spentXp).clamp(0, 99999);

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
          // Top Header with Trophy Illustration
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
                        'Welcome to',
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
                            horizontal: 10, vertical: 4),
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
                            const Icon(Symbols.diamond,
                                size: 15, color: Color(0xFFF59E0B)),
                            const SizedBox(width: 4),
                            Text(
                              '$availableXp XP available',
                              style: TextStyle(
                                color: isDark ? p.amber : const Color(0xFF78350F),
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Golden Trophy graphic
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: isDark
                        ? p.card2
                        : const Color(0xFFFFF3C4),
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

          // Tab Bar (Coupons, How it works, FAQs)
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
                Tab(text: 'Coupons'),
                Tab(text: 'How it works'),
                Tab(text: 'FAQs'),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: p.line),

          // Tab views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _CouponsTab(
                  coupons: _coupons,
                  userXp: availableXp,
                  onRedeem: (c) => _handleRedeem(c, availableXp),
                ),
                const _HowItWorksTab(),
                const _FaqTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CouponReward {
  _CouponReward({
    required this.id,
    required this.title,
    required this.description,
    required this.costXp,
    required this.code,
    required this.expiryDate,
    required this.icon,
    required this.color,
  });

  final String id;
  final String title;
  final String description;
  final int costXp;
  final String code;
  final String expiryDate;
  final IconData icon;
  final Color color;
  bool isUnlocked = false;
}

class _CouponsTab extends StatelessWidget {
  const _CouponsTab({
    required this.coupons,
    required this.userXp,
    required this.onRedeem,
  });

  final List<_CouponReward> coupons;
  final int userXp;
  final ValueChanged<_CouponReward> onRedeem;

  @override
  Widget build(BuildContext context) {
    final p = context.p;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Ticket banner card
        Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: p.line),
          ),
          child: Column(
            children: [
              const Icon(Symbols.confirmation_number,
                  size: 44, color: Color(0xFF38BDF8)),
              const SizedBox(height: 8),
              Text(
                'Coupons you earn will appear here',
                style: TextStyle(
                  color: p.ink2,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),

        Text(
          'Available Study Rewards',
          style: TextStyle(
            color: p.ink,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 14),

        for (final coupon in coupons)
          _CouponTile(
            coupon: coupon,
            userXp: userXp,
            onRedeem: () => onRedeem(coupon),
          ),
      ],
    );
  }
}

class _CouponTile extends StatelessWidget {
  const _CouponTile({
    required this.coupon,
    required this.userXp,
    required this.onRedeem,
  });

  final _CouponReward coupon;
  final int userXp;
  final VoidCallback onRedeem;

  void _copyCode(BuildContext context, String code) {
    Clipboard.setData(ClipboardData(text: code));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('📋 Copied "$code" to clipboard!'),
        backgroundColor: const Color(0xFF10B981),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final canAfford = userXp >= coupon.costXp;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: coupon.isUnlocked
              ? p.green
              : p.line,
          width: coupon.isUnlocked ? 1.5 : 1,
        ),
        boxShadow: p.shadowSm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: coupon.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(coupon.icon, color: coupon.color, size: 28),
          ),
          const SizedBox(width: 14),

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        coupon.title,
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
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: p.amberSoft.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${coupon.costXp} XP',
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
                  coupon.description,
                  style: TextStyle(
                    color: p.ink2,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 6),

                // Expiry Date indicator
                Row(
                  children: [
                    Icon(Symbols.schedule, size: 14, color: p.ink3),
                    const SizedBox(width: 4),
                    Text(
                      coupon.expiryDate,
                      style: TextStyle(
                        color: p.ink3,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Unlocked State with Copy Button OR Redeem Button
                if (coupon.isUnlocked)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: p.greenSoft.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: p.green.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        Icon(Symbols.verified, size: 16, color: p.green),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            coupon.code,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: p.green,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () => _copyCode(context, coupon.code),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Tooltip(
                              message: 'Copy code',
                              child: Icon(Symbols.content_copy,
                                  size: 17, color: p.green),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ElevatedButton(
                    onPressed: canAfford ? onRedeem : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: p.primary,
                      foregroundColor: p.onPrimary,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      canAfford ? 'Redeem Reward' : 'Need more XP',
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

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'How it Works',
          style: TextStyle(
            color: p.ink,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 14),

        // How It Works Card
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: p.line, width: 1.2),
          ),
          child: Column(
            children: [
              // Earning Rewards
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Earning Rewards',
                          style: TextStyle(
                            color: p.ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Gain XP to climb the leagues and unlock bigger study rewards.',
                          style: TextStyle(
                            color: p.ink2,
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: p.card2,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Symbols.featured_seasonal_and_gifts,
                        color: Color(0xFFF43F5E), size: 30),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Divider(color: p.line),
              ),
              // Reward Types
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Reward Types',
                          style: TextStyle(
                            color: p.ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Streak Freezes, 2x XP boosts, special quiz token packs & more.',
                          style: TextStyle(
                            color: p.ink2,
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: p.card2,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Symbols.redeem,
                        color: p.green, size: 30),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),

        Text(
          'Frequently Asked Questions',
          style: TextStyle(
            color: p.ink,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 14),

        const _FaqAccordionList(),
      ],
    );
  }
}

class _FaqTab extends StatelessWidget {
  const _FaqTab();

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Rewards & Leagues FAQ',
          style: TextStyle(
            color: p.ink,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 14),
        const _FaqAccordionList(),
      ],
    );
  }
}

class _FaqAccordionList extends StatelessWidget {
  const _FaqAccordionList();

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final questions = [
      (
        q: 'How can I get LevelUp Rewards?',
        a: 'You get LevelUp Rewards by earning XP! Complete your daily roadmap tasks, review flashcards, and finish practice quizzes to level up your rewards.',
      ),
      (
        q: 'What types of rewards are available in LevelUp?',
        a: 'You can unlock Streak Freeze shields, 2x XP boosts, custom AI practice prompts, and exclusive badge cosmetics for your leaderboard profile.',
      ),
      (
        q: 'How can I redeem my reward?',
        a: 'Navigate to the Coupons tab, select any unlocked reward or redeem using your available XP, and click "Redeem". It is immediately active on your account!',
      ),
      (
        q: 'What does "Opt Out" mean?',
        a: 'If you prefer studying privately without showing up on public league leaderboards, you can turn off public leaderboard participation in your Profile settings.',
      ),
    ];

    return Column(
      children: [
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
              childrenPadding:
                  const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                Text(
                  item.a,
                  style: TextStyle(
                    color: p.ink2,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
