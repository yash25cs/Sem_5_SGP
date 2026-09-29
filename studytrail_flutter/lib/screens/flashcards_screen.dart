import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/stores.dart';
import '../theme/app_theme.dart';
import '../theme/subject_style.dart';
import '../widgets/common.dart';
import '../widgets/data_states.dart';
import '../widgets/generate_sheet.dart';

/// Cards tab — a flashcard review session with flip + deck picker.
class FlashcardsScreen extends StatefulWidget {
  const FlashcardsScreen({super.key, this.onBack});
  final VoidCallback? onBack;

  @override
  State<FlashcardsScreen> createState() => _FlashcardsScreenState();
}

class _FlashcardsScreenState extends State<FlashcardsScreen> {
  /// Name of the deck being reviewed, for the header subtitle.
  String? _sessionDeckName;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<FlashcardStore>().load();
    });
  }

  void _flip() {
    final store = context.read<FlashcardStore>();
    if (!store.revealed) store.reveal();
  }

  Future<void> _grade(SrGrade grade) async {
    await context.read<FlashcardStore>().grade(grade);
  }

  Future<void> _startSession({String? deckId, String? deckName}) async {
    final store = context.read<FlashcardStore>();
    await store.startSession(deckId: deckId);
    if (!mounted) return;
    setState(() => _sessionDeckName = deckName);

    if (store.queue.isEmpty && store.error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing due right now — well done.')),
      );
    }
  }

  /// Writes a new deck from a file the student picks.
  ///
  /// Every generated card is due immediately, so the deck's due count — and the
  /// header's total — jump as soon as the list refreshes.
  Future<void> _generate() async {
    final made = await showGenerateSheet<FlashcardStore>(
      context,
      title: 'Generate flashcards',
      subtitle: 'Written from one file you uploaded',
      actionLabel: 'Generate cards',
      unit: 'cards',
      counts: const [10, 20, 30],
      onGenerate: (store, materialId, count) =>
          store.generateDeck(materialId: materialId, count: count),
    );
    if (!made || !mounted) return;

    final saved = context.read<FlashcardStore>().generatedCards;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(saved == 0
            ? 'Deck created.'
            : '$saved card${saved == 1 ? '' : 's'} added — all due now.'),
      ),
    );
  }



  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final store = context.watch<FlashcardStore>();
    final card = store.current;
    final inSession = card != null;
    final totalDue = store.decks.fold<int>(0, (sum, d) => sum + d.due);

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: RefreshIndicator(
          color: p.primary,
          onRefresh: () => context.read<FlashcardStore>().load(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
            children: [
          Row(
            children: [
              if (widget.onBack != null) ...[
                RoundIconButton(Symbols.arrow_back, onTap: widget.onBack),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Flashcards',
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6)),
                    const SizedBox(height: 2),
                    Text(
                        inSession
                            ? (_sessionDeckName ?? 'Review session')
                            : '$totalDue card${totalDue == 1 ? '' : 's'} due today',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.ink2, fontSize: 13.5)),
                  ],
                ),
              ),
              if (totalDue > 0 && !inSession)
                RoundIconButton(Symbols.play_arrow,
                    plain: false, onTap: () => _startSession()),
            ],
          ),
          const SizedBox(height: 16),

          if (store.error != null)
            ErrorNotice(
              message: store.error!,
              onRetry: () => context.read<FlashcardStore>().load(),
            ),

          if (inSession) ...[
            // session progress
            Row(
              children: [
                Text(
                    'Card ${store.reviewedThisSession + 1} of ${store.queue.length}',
                    style: TextStyle(
                        color: p.ink2,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
                const Spacer(),
                SoftChip('${store.remaining} left',
                    icon: Symbols.timelapse,
                    tone: ChipTone.neutral,
                    small: true),
              ],
            ),
            const SizedBox(height: 10),
            ProgressTrack(store.sessionProgress, color: p.primary, height: 8),
            const SizedBox(height: 22),

            // the card — wrapped in AnimatedSwitcher for smooth card-to-card transition
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) {
                final slide = Tween(
                  begin: const Offset(0.15, 0),
                  end: Offset.zero,
                ).animate(animation);
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: slide, child: child),
                );
              },
              child: _FlipCard(
                key: ValueKey(card.id),
                card: card,
                revealed: store.revealed,
                onFlip: _flip,
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: Text(
                  store.revealed
                      ? 'How well did you know it?'
                      : 'Tap card to reveal answer',
                  style: TextStyle(color: p.ink3, fontSize: 12.5)),
            ),
            const SizedBox(height: 22),

            // rating row — only meaningful once the answer is visible
            Opacity(
              opacity: store.revealed ? 1 : 0.4,
              child: IgnorePointer(
                ignoring: !store.revealed,
                child: Row(
                  children: [
                    Expanded(
                      child: _RateButton('Again', Symbols.replay, p.errorSoft,
                          p.onError, () => _grade(SrGrade.again)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _RateButton(
                          'Hard',
                          Symbols.trending_down,
                          p.amberSoft,
                          p.onAmber,
                          () => _grade(SrGrade.hard)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _RateButton('Good', Symbols.check, p.greenSoft,
                          p.green, () => _grade(SrGrade.good)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ] else if (store.sessionFinished) ...[
            _SessionSummary(
              reviewed: store.reviewedThisSession,
              onDone: () => setState(() => _sessionDeckName = null),
            ),
            const SizedBox(height: 24),
          ],

          // decks
          CardHeader(
            'Your decks',
            action: PillButton('New',
                icon: Symbols.auto_awesome,
                expand: false,
                onTap: store.busy ? null : _generate),
          ),
          if (store.loading && !store.loaded)
            const LoadingBlock(height: 74)
          else if (store.decks.isEmpty)
            EmptyState(
              icon: Symbols.style,
              title: 'No decks yet',
              message:
                  'Generate cards from a file you uploaded, and review them here.',
              actionLabel: store.busy ? null : 'Generate cards',
              onAction: store.busy ? null : _generate,
            )
          else
            for (final deck in store.decks)
              _DeckRow(
                deck: deck,
                onTap: () =>
                    _startSession(deckId: deck.id, deckName: deck.name),
            ),
        ],
      ),
    ),
  ),
);
  }
}

class _FlipCard extends StatefulWidget {
  const _FlipCard({
    super.key,
    required this.card,
    required this.revealed,
    required this.onFlip,
  });

  final Flashcard card;
  final bool revealed;
  final VoidCallback onFlip;

  @override
  State<_FlipCard> createState() => _FlipCardState();
}

class _FlipCardState extends State<_FlipCard> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 420));

  @override
  void didUpdateWidget(_FlipCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.revealed && !oldWidget.revealed) {
      _c.forward();
    } else if (!widget.revealed && oldWidget.revealed) {
      _c.reverse();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onFlip,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final angle = _c.value * 3.14159;
          final isBack = angle > 1.5708;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0012)
              ..rotateY(angle),
            child: isBack
                ? Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..rotateY(3.14159),
                    child: _CardFace(card: widget.card, back: true))
                : _CardFace(card: widget.card, back: false),
          );
        },
      ),
    );
  }
}

class _CardFace extends StatelessWidget {
  const _CardFace({required this.card, required this.back});

  final Flashcard card;
  final bool back;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final text = back ? card.back : card.front;

    return Container(
      constraints: const BoxConstraints(minHeight: 260, maxHeight: 360),
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: back
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [p.primary, p.primary2])
            : null,
        color: back ? null : p.card,
        boxShadow: back ? p.glow : p.shadow,
        border: back ? null : Border.all(color: p.line),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(back ? Symbols.lightbulb : Symbols.help,
                  color: back ? Colors.white : p.primary, size: 22, fill: 1),
              const SizedBox(width: 8),
              Text(back ? 'ANSWER' : 'QUESTION',
                  style: TextStyle(
                      color:
                          back ? Colors.white.withValues(alpha: 0.9) : p.ink3,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1)),
            ],
          ),
          const SizedBox(height: 16),
          Flexible(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Text(text,
                  style: TextStyle(
                      color: back ? Colors.white : p.ink,
                      fontSize: text.length > 200
                          ? 14.5
                          : text.length > 100
                              ? 16
                              : 19,
                      height: 1.45,
                      fontWeight: FontWeight.w700)),
            ),
          ),
          if ((card.unitLabel ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(children: [
              Icon(Symbols.bookmark,
                  color: back ? Colors.white.withValues(alpha: 0.7) : p.ink3,
                  size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(card.unitLabel!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: back
                            ? Colors.white.withValues(alpha: 0.8)
                            : p.ink3,
                        fontSize: 12.5)),
              ),
            ]),
          ],
        ],
      ),
    );
  }
}

/// Shown between finishing a review and going back to the deck list.
class _SessionSummary extends StatelessWidget {
  const _SessionSummary({required this.reviewed, required this.onDone});

  final int reviewed;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return AppCard(
      child: Column(
        children: [
          IconTile(Symbols.celebration, bg: p.greenSoft, fg: p.green, size: 54),
          const SizedBox(height: 14),
          Text('Session complete',
              style: TextStyle(
                  color: p.ink, fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('You reviewed $reviewed card${reviewed == 1 ? '' : 's'}.',
              style: TextStyle(color: p.ink3, fontSize: 13)),
          const SizedBox(height: 16),
          PillButton('Back to decks', onTap: onDone),
        ],
      ),
    );
  }
}

class _RateButton extends StatelessWidget {
  const _RateButton(this.label, this.icon, this.bg, this.fg, this.onTap);
  final String label;
  final IconData icon;
  final Color bg, fg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
        child: Column(
          children: [
            Icon(icon, color: fg, size: 22),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    color: fg, fontSize: 12.5, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

class _DeckRow extends StatelessWidget {
  const _DeckRow({required this.deck, required this.onTap});

  final FlashcardDeck deck;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final style = SubjectStyle.of(
      context,
      name: deck.subjectName ?? deck.name,
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(20),
          boxShadow: p.shadowSm,
        ),
        child: Row(
          children: [
            IconTile(style.icon,
                bg: style.color.withValues(alpha: 0.14),
                fg: style.color,
                size: 46),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(deck.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(
                      [
                        if ((deck.subjectName ?? '').isNotEmpty)
                          deck.subjectName!,
                        '${deck.total} card${deck.total == 1 ? '' : 's'}',
                      ].join(' · '),
                      style: TextStyle(color: p.ink3, fontSize: 12.5)),
                ],
              ),
            ),
            if (deck.due > 0)
              Tag('${deck.due} due',
                  bg: style.color.withValues(alpha: 0.14), fg: style.color)
            else
              Icon(Symbols.check_circle, color: p.green, fill: 1, size: 24),
          ],
        ),
      ),
    );
  }
}
