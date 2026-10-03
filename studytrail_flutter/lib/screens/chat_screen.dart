import 'dart:math' as math;

// Flutter has its own `MaterialType` (for the `Material` widget); hiding it lets
// the app's material-source enum keep the unprefixed name here.
import 'package:flutter/material.dart' hide MaterialType;
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/stores.dart';
import '../theme/app_theme.dart';
import '../widgets/chat_history_panel.dart';
import '../widgets/common.dart';
import '../widgets/data_states.dart';
import '../widgets/material_tile.dart';
import '../widgets/playlist_tile.dart';
import '../widgets/summary_sheet.dart';
import '../widgets/video_link_sheet.dart';

/// Chat tab — the AI study companion Q&A thread.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  /// Enables/disables the send button without rebuilding the whole tree on
  /// every keystroke — only this flag flips.
  bool _canSend = false;

  @override
  void initState() {
    super.initState();
    _input.addListener(() {
      final can = _input.text.trim().isNotEmpty;
      if (can != _canSend) setState(() => _canSend = can);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ChatStore>().load();
      // The header's count comes from this, and the sheet needs it loaded before
      // it opens rather than after.
      context.read<OnboardingStore>().load();
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send([String? preset]) async {
    final store = context.read<ChatStore>();
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || store.sending) return;

    if (preset == null) _input.clear();
    FocusScope.of(context).unfocus();

    // Before awaiting, so the question and the typing dots are on screen while
    // the answer is still being written.
    _scrollToBottom();
    await store.send(text);
    _scrollToBottom();
  }

  /// Jumps to the newest message once the list has laid out the new bubbles.
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Turns one answer into real flashcards. The composer chip that used to say
  /// "Make 5 flashcards" only asked the AI to *type* some into the chat.
  Future<void> _saveCards(String messageId) async {
    final store = context.read<ChatStore>();
    final saved = await store.makeCards(messageId);
    if (!mounted || saved == null) return;
    _toast('$saved card${saved == 1 ? '' : 's'} saved to "Saved from chat" — '
        'find them in Flashcards.');
  }

  /// The materials sheet: what the AI can actually read, and a way to add more.
  ///
  /// It reads [OnboardingStore] because that store already owns the upload →
  /// ingest pipeline, cap included. Sharing it means a file added here behaves
  /// exactly like one added during onboarding.
  void _openMaterials() {
    final p = context.p;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) => _MaterialsSheet(onToast: _toast),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final store = context.watch<ChatStore>();
    final messages = store.messages;

    return Column(
      children: [
        // header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
          child: Row(
            children: [
              // The AI's avatar doubles as the way into past chats, with a
              // small history badge so it reads as a button.
              _HistoryButton(onTap: () => showChatHistory(context)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Trail AI',
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 17,
                            fontWeight: FontWeight.w800)),
                    Row(children: [
                      Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                              color: store.sending ? p.amber : p.green,
                              shape: BoxShape.circle)),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                            store.sending
                                ? 'Thinking…'
                                : 'Knows your syllabus',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: p.ink3, fontSize: 12)),
                      ),
                    ]),
                  ],
                ),
              ),
              // What the AI can read, and the way to add more of it. First in
              // the top-right cluster because an empty library is the single
              // most common reason an answer is unhelpful.
              _MaterialsButton(onTap: _openMaterials),
              // A fresh thread is the closest thing to "clear chat" while
              // history stays on the server.
              RoundIconButton(Symbols.edit_square,
                  plain: false,
                  onTap: store.sending
                      ? null
                      : () => context.read<ChatStore>().newThread()),
            ],
          ),
        ),
        Divider(color: p.line, height: 1),

        // messages
        Expanded(
          child: store.opening || (store.loading && !store.loaded)
              ? const Padding(
                  padding: EdgeInsets.fromLTRB(20, 18, 20, 18),
                  child: LoadingBlock(height: 140),
                )
              : store.messages.isEmpty
                  ? _EmptyThread(onAsk: _send)
                  : ListView.separated(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                      itemCount: messages.length + 1,
                      separatorBuilder: (_, _) => const SizedBox(height: 14),
                      itemBuilder: (context, i) {
                        if (i == 0) return const _DayChip('Conversation');
                        final message = messages[i - 1];
                        if (message.isPending) return const _TypingBubble();
                        final saveable = !message.isUser &&
                            !message.id.startsWith('_local_');
                        return _MessageBlock(
                          message: message,
                          cardsPending: store.cardsPending(message.id),
                          cardsSaved: store.cardsSaved(message.id),
                          onSaveCards: saveable
                              ? () => _saveCards(message.id)
                              : null,
                        );
                      },
                    ),
        ),

        if (store.error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: ErrorNotice(
              message: store.error!,
              onRetry: () => context.read<ChatStore>().clearError(),
            ),
          ),

        // suggestion chips + composer
        Container(
          decoration: BoxDecoration(
            color: p.card,
            border: Border(top: BorderSide(color: p.line)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                SizedBox(
                  height: 34,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.zero,
                    children: [
                      // After an answer, the tutor's own follow-ups; before
                      // one, general starters.
                      if (store.suggestions.isNotEmpty)
                        for (final label in store.suggestions) ...[
                          SoftChip(label,
                              icon: Symbols.subdirectory_arrow_right,
                              tone: ChipTone.primary,
                              small: true,
                              onTap:
                                  store.sending ? null : () => _send(label)),
                          const SizedBox(width: 8),
                        ]
                      else
                        for (final (label, icon) in const [
                          ('Summarize this unit', Symbols.summarize),
                          ('Explain simply', Symbols.lightbulb),
                          ('Give me an example', Symbols.tips_and_updates),
                        ]) ...[
                          SoftChip(label,
                              icon: icon,
                              tone: ChipTone.neutral,
                              small: true,
                              onTap:
                                  store.sending ? null : () => _send(label)),
                          const SizedBox(width: 8),
                        ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: p.card2,
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(color: p.line),
                        ),
                        child: TextField(
                          controller: _input,
                          minLines: 1,
                          maxLines: 4,
                          textCapitalization: TextCapitalization.sentences,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                          style: TextStyle(
                              color: p.ink, fontSize: 14, height: 1.4),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 14),
                            hintText: 'Ask anything about your syllabus…',
                            hintStyle:
                                TextStyle(color: p.ink3, fontSize: 14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _SendButton(
                      enabled: _canSend && !store.sending,
                      sending: store.sending,
                      onTap: _send,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The AI's round avatar, which opens the chat history.
class _HistoryButton extends StatelessWidget {
  const _HistoryButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Semantics(
      button: true,
      label: 'Chat history',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                      colors: [p.primary, p.primary2],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight),
                  boxShadow: p.glow,
                ),
                child: const Icon(Symbols.smart_toy,
                    color: Colors.white, size: 24, fill: 1),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: p.card,
                    shape: BoxShape.circle,
                    border: Border.all(color: p.bg, width: 1.6),
                    boxShadow: p.shadowSm,
                  ),
                  child: Icon(Symbols.history, size: 13, color: p.primary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.enabled,
    required this.sending,
    required this.onTap,
  });

  final bool enabled;
  final bool sending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return InkWell(
      onTap: enabled ? onTap : null,
      customBorder: const CircleBorder(),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled ? p.primary : p.card3,
          boxShadow: enabled ? p.glow : null,
        ),
        child: sending
            ? Padding(
                padding: const EdgeInsets.all(14),
                child: CircularProgressIndicator(
                    color: p.onPrimary, strokeWidth: 2.4),
              )
            : Icon(Symbols.arrow_upward,
                color: enabled ? p.onPrimary : p.ink3,
                size: 24,
                weight: 700),
      ),
    );
  }
}

/// First-run state — a nudge plus starter questions.
class _EmptyThread extends StatelessWidget {
  const _EmptyThread({required this.onAsk});

  final ValueChanged<String> onAsk;

  static const _starters = [
    'Explain the difference between 2NF and 3NF',
    'What should I revise first this week?',
    'Give me a quick summary of my weakest subject',
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 18),
      children: [
        Center(
          child: Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                  colors: [p.primary, p.primary2],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              boxShadow: p.glow,
            ),
            child: const Icon(Symbols.smart_toy,
                color: Colors.white, size: 34, fill: 1),
          ),
        ),
        const SizedBox(height: 18),
        Text('Ask me about your syllabus',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: p.ink, fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(
            'I answer from the material you uploaded, so the explanations match '
            'what you actually have to study.',
            textAlign: TextAlign.center,
            style: TextStyle(color: p.ink3, fontSize: 13, height: 1.5)),
        const SizedBox(height: 22),
        for (final starter in _starters)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              onTap: () => onAsk(starter),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: p.card,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: p.shadowSm,
                ),
                child: Row(children: [
                  Icon(Symbols.auto_awesome, color: p.primary, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(starter,
                        style: TextStyle(
                            color: p.ink2,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600)),
                  ),
                  Icon(Symbols.arrow_forward, color: p.ink3, size: 18),
                ]),
              ),
            ),
          ),
      ],
    );
  }
}

/// One message plus, for AI answers, its citation chips and a way to keep it
/// as flashcards.
class _MessageBlock extends StatelessWidget {
  const _MessageBlock({
    required this.message,
    this.cardsPending = false,
    this.cardsSaved = false,
    this.onSaveCards,
  });

  final ChatMessage message;
  final bool cardsPending;
  final bool cardsSaved;

  /// Null for the student's own messages and for unsaved optimistic ones.
  final VoidCallback? onSaveCards;

  @override
  Widget build(BuildContext context) {
    if (message.isUser) {
      return _Bubble(text: message.text, me: true);
    }

    final p = context.p;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Bubble(text: message.text, me: false),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.only(left: 44),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final citation in message.citations)
                SoftChip(citation.label,
                    icon: Symbols.menu_book,
                    tone: ChipTone.primary,
                    small: true),
              if (onSaveCards != null)
                cardsPending
                    ? SoftChip('Making cards…',
                        customLeading: SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                              strokeWidth: 1.6, color: p.ink3),
                        ),
                        small: true)
                    : cardsSaved
                        ? const SoftChip('Saved as cards',
                            icon: Symbols.check_circle,
                            tone: ChipTone.green,
                            small: true)
                        : SoftChip('Save as flashcards',
                            icon: Symbols.style,
                            small: true,
                            onTap: onSaveCards),
            ],
          ),
        ),
      ],
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip(this.label);
  final String label;
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
            color: p.card2, borderRadius: BorderRadius.circular(999)),
        child: Text(label,
            style: TextStyle(
                color: p.ink3, fontSize: 11.5, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.me});
  final String text;
  final bool me;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final bubble = Container(
      constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.74),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: me ? p.primary : p.card,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(me ? 20 : 6),
          bottomRight: Radius.circular(me ? 6 : 20),
        ),
        boxShadow: me ? null : p.shadowSm,
      ),
      child: SelectableText(text,
          style: TextStyle(
              color: me ? p.onPrimary : p.ink,
              fontSize: 14,
              height: 1.5)),
    );

    if (me) {
      return Align(alignment: Alignment.centerRight, child: bubble);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [p.primary, p.primary2]),
          ),
          child: const Icon(Symbols.smart_toy,
              color: Colors.white, size: 18, fill: 1),
        ),
        const SizedBox(width: 12),
        Flexible(child: bubble),
      ],
    );
  }
}

class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1150),
  )..repeat();

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  /// How lit dot [index] is, 0–1, at cycle position [t].
  ///
  /// Hand-rolled rather than three staggered [Interval] curves: an Interval
  /// clamps outside its window, which parks a dot at full brightness until its
  /// turn comes round again. Wrapping the phase with `%` keeps the pulse
  /// travelling left to right, and the trailing rest is what reads as typing
  /// rather than as three metronomes.
  double _lit(double t, int index) {
    const pulse = 0.55;
    final phase = (t - index * 0.16) % 1.0;
    if (phase > pulse) return 0;
    return math.sin(phase / pulse * math.pi);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [p.primary, p.primary2]),
          ),
          child: const Icon(Symbols.smart_toy,
              color: Colors.white, size: 18, fill: 1),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(20),
            boxShadow: p.shadowSm,
          ),
          child: AnimatedBuilder(
            animation: _wave,
            builder: (context, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 5),
                  _Dot(lit: _lit(_wave.value, i), color: p.ink3),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One typing dot. Rises and brightens together — brightness alone is easy to
/// miss on a dim card, and the lift is what carries the motion.
class _Dot extends StatelessWidget {
  const _Dot({required this.lit, required this.color});

  final double lit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: Offset(0, -3 * lit),
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.3 + 0.7 * lit),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// Header button that opens the materials sheet, badged with how many files the
/// AI has.
///
/// The badge turns amber when nothing is readable yet, because that is exactly
/// the state where answers come back as "nothing you've uploaded covers this"
/// and the cause is otherwise invisible.
class _MaterialsButton extends StatelessWidget {
  const _MaterialsButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final store = context.watch<OnboardingStore>();
    final ready =
        store.uploaded.where((m) => m.status == IngestStatus.embedded).length;
    final needsAttention = ready == 0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        RoundIconButton(Symbols.library_books, plain: false, onTap: onTap),
        Positioned(
          right: -1,
          top: -1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            constraints: const BoxConstraints(minWidth: 17),
            decoration: BoxDecoration(
              color: needsAttention ? p.amber : p.primary,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: p.bg, width: 1.6),
            ),
            child: Text(
              // Library items: a playlist counts once, like on its slot.
              '${store.itemCount}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }
}

/// The sheet behind the header button: everything the AI can read, plus the way
/// to add more.
class _MaterialsSheet extends StatelessWidget {
  const _MaterialsSheet({required this.onToast});

  final ValueChanged<String> onToast;

  Future<void> _add(BuildContext context) async {
    final store = context.read<OnboardingStore>();
    final count = await store.pickAndUpload(MaterialType.syllabusPdf);
    final failure = store.error;
    if (failure != null) {
      // A non-zero count alongside an error means the batch stopped partway.
      onToast(count == 0 ? failure : '$count added, then: $failure');
    } else if (count > 0) {
      onToast(count == 1 ? 'File added — ask away' : '$count files added');
    }
  }

  Future<void> _snap(BuildContext context) async {
    final store = context.read<OnboardingStore>();
    final count = await store.snapAndUpload();
    final failure = store.error;
    if (failure != null) {
      onToast(failure);
    } else if (count > 0) {
      onToast('Photo added — ask away once it says Ready');
    }
  }

  Future<void> _addVideo(BuildContext context) =>
      addVideoLink(context, toast: onToast);

  Future<void> _retry(BuildContext context, StudyMaterial material) async {
    final store = context.read<OnboardingStore>();
    final ok = await store.reingest(material);
    onToast(ok ? 'Reading it again…' : store.error ?? 'Could not read that file');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final store = context.watch<OnboardingStore>();
    final materials = store.uploaded;
    final ready =
        materials.where((m) => m.status == IngestStatus.embedded).length;
    // A playlist's videos read in the background and hold nothing up.
    final working = store.busy || store.addingLink;

    Widget tile(StudyMaterial material) => MaterialTile(
          key: ValueKey(material.id),
          material: material,
          onRetry: store.busy ? null : () => _retry(context, material),
          onRemove: store.busy
              ? null
              : () => context.read<OnboardingStore>().removeMaterial(material),
          onSummarize: () {
            final nav = Navigator.of(context);
            final materialId = material.id;
            final title = material.displayName;
            nav.pop();
            SummarySheet.show(nav.context,
                materialId: materialId, title: title);
          },
        );

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.78,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Your materials',
                            style: TextStyle(
                                color: p.ink,
                                fontSize: 18,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 3),
                        Text(
                            '${store.itemCount} of '
                            '${OnboardingStore.maxMaterials} items · '
                            '$ready ready to search',
                            style: TextStyle(color: p.ink3, fontSize: 12.5)),
                      ],
                    ),
                  ),
                  RoundIconButton(Symbols.close,
                      onTap: () => Navigator.of(context).maybePop()),
                ],
              ),
              const SizedBox(height: 6),

              if (store.error != null) ...[
                const SizedBox(height: 8),
                ErrorNotice(
                  message: store.error!,
                  onRetry: () => context.read<OnboardingStore>().clearError(),
                ),
              ],

              // Said plainly, because it is the whole reason an answer can come
              // back empty: the AI only sees files that finished processing.
              if (materials.isNotEmpty && ready == 0) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Symbols.info, color: p.amber, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                          "None of these are searchable yet, so answers won't "
                          'use them. Retry any that failed.',
                          style: TextStyle(
                              color: p.ink2, fontSize: 12, height: 1.45)),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 14),
              Flexible(
                child: !store.hasMaterial
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 26),
                        child: Column(
                          children: [
                            Icon(Symbols.folder_open, color: p.ink3, size: 34),
                            const SizedBox(height: 10),
                            Text('Nothing uploaded yet',
                                style: TextStyle(
                                    color: p.ink,
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text(
                                'Add your syllabus, notes or a YouTube lecture '
                                'and I can answer from them.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: p.ink3, fontSize: 12.5, height: 1.45)),
                          ],
                        ),
                      )
                    : ListView(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        children: [
                          for (final playlist in store.playlists)
                            PlaylistTile(
                              key: ValueKey(playlist.id),
                              playlist: playlist,
                              progress: store.progressOf(playlist),
                              videos: store.videosOf(playlist),
                              reading: store.activePlaylistId == playlist.id,
                              onResume: store.readingPlaylists
                                  ? null
                                  : () => context
                                      .read<OnboardingStore>()
                                      .resumeImports(),
                              onRetryFailed: () => context
                                  .read<OnboardingStore>()
                                  .retryFailed(playlist),
                              onRemove: store.busy
                                  ? null
                                  : () => context
                                      .read<OnboardingStore>()
                                      .removePlaylist(playlist),
                              videoBuilder: tile,
                            ),
                          for (final material in store.standalone)
                            tile(material),
                        ],
                      ),
              ),
              const SizedBox(height: 8),
              PillButton(
                store.atLimit
                    ? 'Limit reached — remove one first'
                    : 'Add a PDF or notes',
                icon: working ? null : Symbols.upload_file,
                variant:
                    store.atLimit ? PillVariant.outline : PillVariant.primary,
                onTap: working || store.atLimit ? null : () => _add(context),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: PillButton('Snap notes',
                        icon: Symbols.photo_camera,
                        variant: PillVariant.outline,
                        onTap: working || store.atLimit
                            ? null
                            : () => _snap(context)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: PillButton(
                        store.addingLink
                            ? store.linkProgress ?? 'Opening…'
                            : 'YouTube',
                        icon: store.addingLink ? null : Symbols.smart_display,
                        variant: PillVariant.outline,
                        onTap: working || store.atLimit
                            ? null
                            : () => _addVideo(context)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // The real ceilings, not the bucket's: `embed-material` refuses a
              // PDF or photo over 14 MB and a text file over 2 MB, and a file
              // that uploads but can't be read is worse than one that's refused.
              Text(
                  'PDF or photo up to 14 MB · TXT or MD up to 2 MB · '
                  'YouTube videos or playlists with captions',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.ink3, fontSize: 11.5)),
            ],
          ),
        ),
      ),
    );
  }
}
