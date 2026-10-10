import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/stores.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/data_states.dart';
import '../widgets/nav.dart';

String _ago(DateTime at) {
  final d = DateTime.now().difference(at.toLocal());
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  if (d.inDays < 7) return '${d.inDays} d ago';
  final l = at.toLocal();
  return '${l.day}/${l.month}/${l.year}';
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
  );
}

/// Report or block, for another student's doubt or answer.
Future<void> _moderate(
  BuildContext context, {
  required String userId,
  required String name,
  String? doubtId,
  String? answerId,
}) async {
  final p = context.p;
  final store = context.read<DoubtStore>();
  final action = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: p.card,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sheetCtx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Text(name,
              style: TextStyle(
                  color: p.ink, fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          ListTile(
            leading: Icon(Symbols.flag, color: p.error),
            title: Text('Report', style: TextStyle(color: p.ink)),
            onTap: () => Navigator.of(sheetCtx).pop('report'),
          ),
          ListTile(
            leading: Icon(Symbols.block, color: p.ink2),
            title: Text('Block — hide everything they post',
                style: TextStyle(color: p.ink)),
            onTap: () => Navigator.of(sheetCtx).pop('block'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  if (action == 'block') {
    final ok = await store.block(userId);
    if (context.mounted) {
      _toast(
          context, ok ? '$name blocked.' : store.error ?? 'Could not block.');
    }
    return;
  }
  final reason = await showDialog<String>(
    context: context,
    builder: (dialogCtx) => SimpleDialog(
      backgroundColor: p.card,
      title: Text('Why are you reporting this?',
          style: TextStyle(color: p.ink, fontSize: 17)),
      children: [
        for (final (value, label) in const [
          ('spam', 'Spam or advertising'),
          ('harassment', 'Bullying or harassment'),
          ('inappropriate', 'Inappropriate content'),
          ('other', 'Something else'),
        ])
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogCtx).pop(value),
            child: Text(label, style: TextStyle(color: p.ink2)),
          ),
      ],
    ),
  );
  if (reason == null || !context.mounted) return;
  final ok =
      await store.report(reason: reason, doubtId: doubtId, answerId: answerId);
  if (context.mounted) {
    _toast(
        context,
        ok
            ? 'Reported. Thanks — it will be reviewed.'
            : store.error ?? 'Could not send the report.');
  }
}

/// The doubt board, shared by every student (0029): ask, answer, upvote,
/// mark solved.
class DoubtBoardScreen extends StatefulWidget {
  const DoubtBoardScreen({super.key, this.onBack});

  final VoidCallback? onBack;

  @override
  State<DoubtBoardScreen> createState() => _DoubtBoardScreenState();
}

class _DoubtBoardScreenState extends State<DoubtBoardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<DoubtStore>().load();
    });
  }

  Future<void> _ask() async {
    final posted = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.p.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (_) => const _AskSheet(),
    );
    if (posted == null || !mounted) return;
    _openThread(posted);
  }

  void _openThread(String id) {
    context.read<DoubtStore>().open(id);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DoubtThreadScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final store = context.watch<DoubtStore>();
    return Scaffold(
      backgroundColor: p.bg,
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('ask-doubt'),
        onPressed: _ask,
        backgroundColor: p.primary,
        icon: const Icon(Symbols.add_comment, color: Colors.white),
        label: const Text('Ask a doubt',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
      ),
      body: Column(
        children: [
          const TopInset(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                RoundIconButton(Symbols.arrow_back,
                    onTap: widget.onBack ??
                        () => Navigator.of(context).maybePop()),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Doubt board',
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 19,
                              fontWeight: FontWeight.w800)),
                      Text('Ask everyone · students and AI answer',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: p.ink3, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final MapEntry(key: key, value: label)
                      in DoubtStore.filters.entries)
                    SoftChip(label,
                        tone: store.filter == key
                            ? ChipTone.primary
                            : ChipTone.neutral,
                        onTap: () => store.setFilter(key)),
                ],
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              color: p.primary,
              onRefresh: store.load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
                children: [
                  if (store.error != null)
                    ErrorNotice(message: store.error!, onRetry: store.load)
                  else if (store.loading && store.doubts.isEmpty)
                    const LoadingBlock(height: 160)
                  else if (store.doubts.isEmpty)
                    EmptyState(
                      icon: Symbols.forum,
                      title: store.filter == 'mine'
                          ? "You haven't asked anything yet"
                          : 'No doubts here yet',
                      message: 'Stuck on something? Ask it here — other students '
                          'can answer, and the AI can give a first answer '
                          'from your notes.',
                      actionLabel: 'Ask a doubt',
                      onAction: _ask,
                    )
                  else
                    for (final d in store.doubts) ...[
                      _DoubtTile(doubt: d, onTap: () => _openThread(d.id)),
                      const SizedBox(height: 10),
                    ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DoubtTile extends StatelessWidget {
  const _DoubtTile({required this.doubt, required this.onTap});

  final DoubtSummary doubt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return AppCard(
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GradAvatar(doubt.initial, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(doubt.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 14.5,
                        height: 1.3,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                    [
                      doubt.isMine ? 'You' : doubt.author,
                      _ago(doubt.createdAt),
                      if ((doubt.subject ?? '').isNotEmpty) doubt.subject!,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.ink3, fontSize: 12)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    SoftChip(
                        doubt.answers == 1
                            ? '1 answer'
                            : '${doubt.answers} answers',
                        icon: Symbols.chat_bubble,
                        small: true),
                    if (doubt.solved)
                      const SoftChip('Solved',
                          icon: Symbols.check_circle,
                          tone: ChipTone.green,
                          small: true),
                    if (doubt.hasAi)
                      const SoftChip('AI answered',
                          icon: Symbols.auto_awesome,
                          tone: ChipTone.primary,
                          small: true),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A new doubt: a title, optional details and subject, and whether the AI
/// should give a first answer from the asker's notes.
class _AskSheet extends StatefulWidget {
  const _AskSheet();

  @override
  State<_AskSheet> createState() => _AskSheetState();
}

class _AskSheetState extends State<_AskSheet> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _subject = TextEditingController();
  bool _ai = true;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _subject.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    final title = _title.text.trim();
    if (title.length < 5) {
      setState(() => _error = 'Say a bit more in the title.');
      return;
    }
    final store = context.read<DoubtStore>();
    final id = await store.post(
      title: title,
      body: _body.text.trim().isEmpty ? null : _body.text.trim(),
      subject: _subject.text.trim().isEmpty ? null : _subject.text.trim(),
    );
    if (!mounted) return;
    if (id == null) {
      setState(() => _error = store.error ?? 'Could not post that.');
      return;
    }
    // The first answer comes while the thread opens.
    if (_ai) store.askAi().ignore();
    Navigator.of(context).pop(id);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final busy = context.watch<DoubtStore>().busy;

    InputDecoration field(String hint) => InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: p.ink3, fontSize: 14),
          filled: true,
          fillColor: p.card2,
          counterText: '',
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        );

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ask everyone',
                style: TextStyle(
                    color: p.ink, fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Other students see your name and your question.',
                style: TextStyle(color: p.ink3, fontSize: 12.5)),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('doubt-title'),
              controller: _title,
              maxLength: 200,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(color: p.ink, fontSize: 14.5),
              decoration: field('Your doubt, in one line'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _body,
              minLines: 3,
              maxLines: 6,
              maxLength: 4000,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(color: p.ink, fontSize: 14),
              decoration: field('Details — what you tried, where you got stuck '
                  '(optional)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _subject,
              maxLength: 80,
              style: TextStyle(color: p.ink, fontSize: 14),
              decoration: field('Subject, e.g. DBMS (optional)'),
            ),
            const SizedBox(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _ai,
              onChanged: busy ? null : (v) => setState(() => _ai = v),
              title: Text('Get a first answer from AI',
                  style: TextStyle(
                      color: p.ink, fontSize: 14, fontWeight: FontWeight.w700)),
              subtitle: Text(
                  'Written from your own notes; other students see it '
                  'too.',
                  style: TextStyle(color: p.ink3, fontSize: 12)),
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(_error!,
                  style: TextStyle(
                      color: p.error,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 12),
            PillButton(busy ? 'Posting…' : 'Post doubt',
                icon: busy ? null : Symbols.send, onTap: busy ? null : _post),
          ],
        ),
      ),
    );
  }
}

/// One doubt and its answers.
class DoubtThreadScreen extends StatefulWidget {
  const DoubtThreadScreen({super.key});

  @override
  State<DoubtThreadScreen> createState() => _DoubtThreadScreenState();
}

class _DoubtThreadScreenState extends State<DoubtThreadScreen> {
  final _answer = TextEditingController();

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _answer.text.trim();
    if (text.isEmpty) return;
    FocusScope.of(context).unfocus();
    final store = context.read<DoubtStore>();
    final ok = await store.answer(text);
    if (!mounted) return;
    if (ok) {
      _answer.clear();
    } else {
      _toast(context, store.error ?? 'Could not post your answer.');
    }
  }

  Future<void> _deleteDoubt() async {
    final p = context.p;
    final store = context.read<DoubtStore>();
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: p.card,
        title: Text('Delete this doubt?', style: TextStyle(color: p.ink)),
        content:
            Text('Its answers go with it.', style: TextStyle(color: p.ink2)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: Text('Delete', style: TextStyle(color: p.error))),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    final ok = await store.deleteDoubt();
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).maybePop();
    } else {
      _toast(context, store.error ?? 'Could not delete it.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final store = context.watch<DoubtStore>();
    final t = store.thread;

    return Scaffold(
      backgroundColor: p.bg,
      body: Column(
        children: [
          const TopInset(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                RoundIconButton(Symbols.arrow_back,
                    onTap: () => Navigator.of(context).maybePop()),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Doubt',
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 19,
                          fontWeight: FontWeight.w800)),
                ),
                if (t != null && t.isMine)
                  RoundIconButton(Symbols.delete,
                      color: p.error, onTap: _deleteDoubt)
                else if (t != null)
                  RoundIconButton(Symbols.more_vert,
                      onTap: () => _moderate(context,
                          userId: t.userId, name: t.author, doubtId: t.id)),
              ],
            ),
          ),
          Expanded(
            child: t == null
                ? (store.error != null
                    ? Padding(
                        padding: const EdgeInsets.all(20),
                        child: ErrorNotice(message: store.error!),
                      )
                    : const Center(child: CircularProgressIndicator()))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                    children: [
                      _DoubtHeader(thread: t),
                      if (t.isMine && !t.hasAi) ...[
                        const SizedBox(height: 12),
                        store.askingAi
                            ? const _AiThinking()
                            : PillButton('Get a first answer from AI',
                                icon: Symbols.auto_awesome,
                                variant: PillVariant.outline,
                                onTap: store.busy
                                    ? null
                                    : () async {
                                        final ok = await store.askAi();
                                        if (!ok && context.mounted) {
                                          _toast(
                                              context,
                                              store.error ??
                                                  'The AI could not answer.');
                                        }
                                      }),
                      ] else if (store.askingAi) ...[
                        const SizedBox(height: 12),
                        const _AiThinking(),
                      ],
                      const SizedBox(height: 18),
                      Text(
                          t.answers.isEmpty
                              ? 'No answers yet'
                              : t.answers.length == 1
                                  ? '1 answer'
                                  : '${t.answers.length} answers',
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 15,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 10),
                      for (final a in t.answers) ...[
                        _AnswerCard(
                          answer: a,
                          thread: t,
                          busy: store.busy,
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
          ),
          if (t != null)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              decoration: BoxDecoration(
                color: p.card,
                border: Border(top: BorderSide(color: p.line)),
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: p.card2,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: TextField(
                          key: const ValueKey('doubt-answer'),
                          controller: _answer,
                          minLines: 1,
                          maxLines: 4,
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(6000)
                          ],
                          textCapitalization: TextCapitalization.sentences,
                          style: TextStyle(color: p.ink, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: t.isMine
                                ? 'Add a detail or an answer…'
                                : 'Write an answer…',
                            hintStyle: TextStyle(color: p.ink3, fontSize: 14),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: store.busy ? null : _send,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: p.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Symbols.send,
                            color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DoubtHeader extends StatelessWidget {
  const _DoubtHeader({required this.thread});

  final DoubtThread thread;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GradAvatar(thread.initial, size: 32),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                    '${thread.isMine ? 'You' : thread.author} · '
                    '${_ago(thread.createdAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: p.ink2,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700)),
              ),
              if (thread.solved)
                const SoftChip('Solved',
                    icon: Symbols.check_circle,
                    tone: ChipTone.green,
                    small: true),
            ],
          ),
          const SizedBox(height: 12),
          if ((thread.subject ?? '').isNotEmpty) ...[
            SoftChip(thread.subject!, small: true, tone: ChipTone.primary),
            const SizedBox(height: 8),
          ],
          Text(thread.title,
              style: TextStyle(
                  color: p.ink,
                  fontSize: 17,
                  height: 1.35,
                  fontWeight: FontWeight.w800)),
          if ((thread.body ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(thread.body!,
                style: TextStyle(color: p.ink2, fontSize: 14, height: 1.5)),
          ],
        ],
      ),
    );
  }
}

class _AiThinking extends StatelessWidget {
  const _AiThinking();

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Row(
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2.4, color: p.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text('The AI is reading your notes…',
              style: TextStyle(
                  color: p.ink2, fontSize: 13, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

class _AnswerCard extends StatelessWidget {
  const _AnswerCard({
    required this.answer,
    required this.thread,
    required this.busy,
  });

  final DoubtAnswer answer;
  final DoubtThread thread;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final store = context.read<DoubtStore>();
    final solving = thread.solvedAnswerId == answer.id;
    final who = answer.isAi
        ? 'AI · from ${thread.isMine ? 'your' : "${answer.author}'s"} notes'
        : answer.isMine
            ? 'You'
            : answer.author;

    return AppCard(
      padding: const EdgeInsets.all(14),
      color: solving ? p.greenSoft : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              answer.isAi
                  ? IconTile(Symbols.auto_awesome,
                      bg: p.primarySoft, fg: p.primary, size: 28, radius: 9)
                  : GradAvatar(answer.initial, size: 28),
              const SizedBox(width: 8),
              Expanded(
                child: Text('$who · ${_ago(answer.createdAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: p.ink2,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
              if (answer.isMine)
                GestureDetector(
                  onTap: busy ? null : () => store.deleteAnswer(answer.id),
                  child: Icon(Symbols.delete, size: 18, color: p.ink3),
                )
              else if (!answer.isAi)
                GestureDetector(
                  onTap: () => _moderate(context,
                      userId: answer.userId,
                      name: answer.author,
                      answerId: answer.id),
                  child: Icon(Symbols.more_horiz, size: 20, color: p.ink3),
                ),
            ],
          ),
          const SizedBox(height: 10),
          SelectableText(answer.body,
              style: TextStyle(color: p.ink, fontSize: 14, height: 1.5)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SoftChip(
                  answer.votes == 0 ? 'Helpful' : 'Helpful · ${answer.votes}',
                  icon: Symbols.thumb_up,
                  small: true,
                  tone: answer.voted ? ChipTone.primary : ChipTone.neutral,
                  onTap: answer.isMine || busy
                      ? null
                      : () => store.vote(answer.id)),
              if (solving)
                SoftChip(thread.isMine ? 'Solved it · undo' : 'Solved it',
                    icon: Symbols.check_circle,
                    small: true,
                    tone: ChipTone.green,
                    onTap: thread.isMine && !busy
                        ? () => store.markSolved(null)
                        : null)
              else if (thread.isMine)
                SoftChip('Mark as solved',
                    icon: Symbols.done,
                    small: true,
                    onTap: busy ? null : () => store.markSolved(answer.id)),
            ],
          ),
        ],
      ),
    );
  }
}
