import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/stores.dart';
import '../theme/app_theme.dart';
import 'common.dart';
import 'data_states.dart';

/// Slides the student's past chats in from the left, the way other AI chat
/// apps keep their history: newest first, grouped by day, with New chat at
/// the top. Tapping one opens it in the chat screen.
///
/// A dialog route rather than a [Scaffold] drawer so it covers the whole
/// screen, bottom navigation included, like a real side panel.
Future<void> showChatHistory(BuildContext context) {
  context.read<ChatStore>().loadHistory();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close chat history',
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (_, _, _) => const _HistoryPanel(),
    transitionBuilder: (_, animation, _, child) => SlideTransition(
      position: Tween(begin: const Offset(-1, 0), end: Offset.zero).animate(
          CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic)),
      child: child,
    ),
  );
}

class _HistoryPanel extends StatelessWidget {
  const _HistoryPanel();

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final store = context.watch<ChatStore>();
    final width = MediaQuery.of(context).size.width;
    final groups = groupChatsByDay(store.history, DateTime.now());

    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: p.bg,
        elevation: 12,
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: width * 0.84 > 360 ? 360 : width * 0.84,
          height: double.infinity,
          child: SafeArea(
            right: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 10, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('Chats',
                            style: TextStyle(
                                color: p.ink,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4)),
                      ),
                      RoundIconButton(Symbols.close,
                          onTap: () => Navigator.of(context).maybePop()),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                  child: PillButton('New chat',
                      icon: Symbols.edit_square,
                      onTap: store.sending
                          ? null
                          : () {
                              store.newThread();
                              Navigator.of(context).maybePop();
                            }),
                ),
                if (store.historyError != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ErrorNotice(
                      message: store.historyError!,
                      onRetry: store.loadHistory,
                    ),
                  ),
                Expanded(
                  child: store.historyLoading && store.history.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: LoadingBlock(height: 160),
                        )
                      : store.history.isEmpty
                          ? _Empty(loaded: store.historyLoaded)
                          : ListView(
                              padding: const EdgeInsets.fromLTRB(10, 4, 10, 20),
                              children: [
                                for (final (label, threads) in groups) ...[
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        10, 14, 10, 6),
                                    child: Text(label.toUpperCase(),
                                        style: TextStyle(
                                            color: p.ink3,
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.8)),
                                  ),
                                  for (final thread in threads)
                                    _ThreadRow(
                                      thread: thread,
                                      open: store.thread?.id == thread.id,
                                    ),
                                ],
                              ],
                            ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThreadRow extends StatelessWidget {
  const _ThreadRow({required this.thread, required this.open});

  final ChatThread thread;
  final bool open;

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String _when(BuildContext context) {
    final at = thread.createdAt;
    if (at == null) return '';
    final now = DateTime.now();
    if (at.year == now.year && at.month == now.month && at.day == now.day) {
      return TimeOfDay.fromDateTime(at).format(context);
    }
    final date = '${at.day} ${_months[at.month - 1]}';
    return at.year == now.year ? date : '$date ${at.year}';
  }

  Future<void> _delete(BuildContext context) async {
    final p = context.p;
    final store = context.read<ChatStore>();
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: p.card,
        title: Text('Delete this chat?',
            style: TextStyle(color: p.ink, fontWeight: FontWeight.w800)),
        content: Text(
            '"${thread.displayTitle}" and its answers will be deleted.',
            style: TextStyle(color: p.ink2, height: 1.45)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Cancel', style: TextStyle(color: p.ink3)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Delete',
                style: TextStyle(color: p.error, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (yes == true) await store.deleteThread(thread);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: open ? p.primarySoft : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            context.read<ChatStore>().openThread(thread);
            Navigator.of(context).maybePop();
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 2, 8),
            child: Row(
              children: [
                Icon(Symbols.chat_bubble,
                    size: 18, color: open ? p.primary : p.ink3),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(thread.displayTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 14,
                              height: 1.3,
                              fontWeight:
                                  open ? FontWeight.w800 : FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(_when(context),
                          style: TextStyle(color: p.ink3, fontSize: 11.5)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Delete chat',
                  icon: Icon(Symbols.delete, size: 20, color: p.ink3),
                  onPressed: () => _delete(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.loaded});
  final bool loaded;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 30, 28, 0),
      child: Column(
        children: [
          Icon(Symbols.forum, color: p.ink3, size: 34),
          const SizedBox(height: 10),
          Text(loaded ? 'No chats yet' : '',
              style: TextStyle(
                  color: p.ink, fontSize: 14.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
              'Each time you open the app a new chat starts. Your earlier '
              'ones are kept here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: p.ink3, fontSize: 12.5, height: 1.45)),
        ],
      ),
    );
  }
}

/// Today, Yesterday, Previous 7 days, Earlier — in that order, empty groups
/// left out. [now] is a parameter so the grouping can be tested.
List<(String, List<ChatThread>)> groupChatsByDay(
    List<ChatThread> threads, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final buckets = <String, List<ChatThread>>{
    'Today': [],
    'Yesterday': [],
    'Previous 7 days': [],
    'Earlier': [],
  };
  for (final thread in threads) {
    final at = thread.createdAt ?? now;
    final day = DateTime(at.year, at.month, at.day);
    // Rounded hours, not inDays: a day with a clock change is 23 or 25 hours.
    final daysAgo = (today.difference(day).inHours / 24).round();
    final key = daysAgo <= 0
        ? 'Today'
        : daysAgo == 1
            ? 'Yesterday'
            : daysAgo <= 7
                ? 'Previous 7 days'
                : 'Earlier';
    buckets[key]!.add(thread);
  }
  return [
    for (final entry in buckets.entries)
      if (entry.value.isNotEmpty) (entry.key, entry.value),
  ];
}
