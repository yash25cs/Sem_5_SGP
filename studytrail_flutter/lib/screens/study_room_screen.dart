import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../data/supabase_client.dart';
import '../models/models.dart';
import '../state/stores.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/nav.dart';

/// Screen displayed when the student is inside an active Study Buddy Room.
/// Provides synchronized timer, live peer presence, and real-time room chat.
class StudyRoomScreen extends StatefulWidget {
  const StudyRoomScreen({super.key, this.onLeave});

  final VoidCallback? onLeave;

  @override
  State<StudyRoomScreen> createState() => _StudyRoomScreenState();
}

class _StudyRoomScreenState extends State<StudyRoomScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  void _copyCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    _toast('Invite code $code copied to clipboard!');
  }

  Future<void> _confirmLeave() async {
    final store = context.read<RoomStore>();
    final isHost = store.isHost;
    final p = context.p;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: p.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(isHost ? 'Close this room?' : 'Leave study room?',
            style: TextStyle(
                color: p.ink, fontSize: 18, fontWeight: FontWeight.w800)),
        content: Text(
            isHost
                ? 'As host, closing the room will disconnect all study buddies.'
                : 'You can rejoin anytime using the room code.',
            style: TextStyle(color: p.ink2, fontSize: 14, height: 1.45)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text('Cancel', style: TextStyle(color: p.ink3)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(isHost ? 'Close Room' : 'Leave',
                style: TextStyle(color: p.error, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      if (isHost) {
        final ok = await store.closeCurrentRoom();
        if (!ok) {
          _toast(store.error ?? 'Could not close the room. Try again.');
          return;
        }
      } else {
        await store.leaveCurrentRoom();
      }
      _exit();
    }
  }

  void _exit() {
    if (!mounted) return;
    widget.onLeave?.call();
    Navigator.of(context).pop();
  }

  /// After the host closes the room there is nothing to confirm.
  Future<void> _leaveClosedRoom() async {
    await context.read<RoomStore>().leaveCurrentRoom();
    _exit();
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text;
    if (text.trim().isEmpty) return;
    _messageController.clear();
    _scrollToBottom();
    final store = context.read<RoomStore>();
    final ok = await store.sendMessage(text);
    if (!ok && mounted) {
      // Hand the text back rather than making them retype it.
      if (_messageController.text.isEmpty) _messageController.text = text;
      _toast(store.error ?? 'Message not sent. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final store = context.watch<RoomStore>();
    final room = store.currentRoom;
    final closedNotice = store.closedNotice;

    if (room == null || closedNotice != null) {
      return PopScope(
        canPop: room == null,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _leaveClosedRoom();
        },
        child: Scaffold(
          backgroundColor: p.bg,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Symbols.door_front, size: 44, color: p.ink3),
                  const SizedBox(height: 12),
                  Text(closedNotice ?? 'Room closed or not found',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  PillButton('Back to Lobby',
                      expand: false,
                      onTap: room == null
                          ? () => Navigator.of(context).pop()
                          : _leaveClosedRoom),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final isHost = store.isHost;
    final presence = store.onlinePresence;

    // The system back gesture used to pop this screen without leaving: the
    // channel, the membership row, and (for a host) the room all stayed open.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
      backgroundColor: p.bg,
      body: Column(
        children: [
          const TopInset(),

          // ── App Bar ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                RoundIconButton(
                  Symbols.arrow_back,
                  onTap: _confirmLeave,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              room.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: p.ink,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (isHost)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: p.amberSoft,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'HOST',
                                style: TextStyle(
                                  color: p.onAmber,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      GestureDetector(
                        onTap: () => _copyCode(room.inviteCode),
                        child: Row(
                          children: [
                            Text(
                              'Code: ${room.inviteCode}',
                              style: TextStyle(
                                color: p.primary,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(Symbols.content_copy,
                                size: 14, color: p.primary),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Online count badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: p.greenSoft,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: p.green,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${store.onlineCount} online',
                        style: TextStyle(
                          color: p.green,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Scrollable Upper Content (Timer + Presence) ──
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                // ── Shared Pomodoro Card ──
                AppCard(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                store.isFocus
                                    ? Symbols.timer
                                    : Symbols.coffee,
                                color: store.isFocus ? p.primary : p.amber,
                                size: 20,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                store.isFocus ? 'FOCUS BLOCK' : 'BREAK TIME',
                                style: TextStyle(
                                  color: store.isFocus ? p.primary : p.amber,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ),
                          if (!isHost)
                            Row(
                              children: [
                                Icon(Symbols.sync,
                                    size: 14, color: p.ink3),
                                const SizedBox(width: 4),
                                Text(
                                  'Sync with host',
                                  style: TextStyle(
                                      color: p.ink3,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Countdown display
                      Text(
                        store.timerDisplay,
                        style: TextStyle(
                          color: p.ink,
                          fontSize: 48,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.5,
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Progress bar
                      ProgressTrack(
                        store.timerProgress,
                        color: store.isFocus ? p.primary : p.amber,
                        height: 8,
                      ),
                      const SizedBox(height: 16),

                      // Host controls
                      if (isHost) ...[
                        Row(
                          children: [
                            Expanded(
                              child: PillButton(
                                store.timerRunning ? 'Pause' : 'Start Focus',
                                icon: store.timerRunning
                                    ? Symbols.pause
                                    : Symbols.play_arrow,
                                variant: store.timerRunning
                                    ? PillVariant.outline
                                    : PillVariant.primary,
                                onTap: store.toggleTimer,
                              ),
                            ),
                            const SizedBox(width: 10),
                            RoundIconButton(
                              Symbols.restart_alt,
                              plain: false,
                              color: p.ink2,
                              onTap: store.resetTimer,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TextButton.icon(
                              onPressed: () => store.switchPhase(
                                  store.isFocus ? 'break' : 'focus'),
                              icon: Icon(
                                store.isFocus
                                    ? Symbols.coffee
                                    : Symbols.bolt,
                                size: 16,
                                color: p.primary,
                              ),
                              label: Text(
                                store.isFocus
                                    ? 'Switch to Break'
                                    : 'Switch to Focus',
                                style: TextStyle(
                                  color: p.primary,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        Text(
                          'Host controls the shared timer for the room.',
                          style: TextStyle(
                              color: p.ink3,
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // ── Study Buddies in Room (Presence) ──
                Text(
                  'Buddies in Room (${presence.length})',
                  style: TextStyle(
                    color: p.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                if (presence.isEmpty)
                  Text('Waiting for buddies to connect…',
                      style: TextStyle(color: p.ink3, fontSize: 13))
                else
                  SizedBox(
                    height: 82,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: presence.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        final peer = presence[index];
                        return Column(
                          children: [
                            Stack(
                              children: [
                                GradAvatar(peer.avatarInitial, size: 46),
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    width: 13,
                                    height: 13,
                                    decoration: BoxDecoration(
                                      // Green focusing, amber on break,
                                      // grey when their timer isn't running.
                                      color: switch (peer.studyStatus) {
                                        'focusing' => p.green,
                                        'on_break' => p.amber,
                                        _ => p.ink3,
                                      },
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: p.bg, width: 2),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            SizedBox(
                              width: 60,
                              child: Text(
                                peer.fullName.split(' ').first,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: p.ink,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),

                const SizedBox(height: 14),

                // ── Room Chat Header ──
                Row(
                  children: [
                    Icon(Symbols.chat, size: 18, color: p.ink2),
                    const SizedBox(width: 6),
                    Text(
                      'Room Chat',
                      style: TextStyle(
                        color: p.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // ── Chat Messages ──
                if (store.messages.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'No messages yet. Say hi to your study buddies! 👋',
                        style: TextStyle(color: p.ink3, fontSize: 13),
                      ),
                    ),
                  )
                else
                  for (final msg in store.messages) ...[
                    _ChatMessageBubble(
                      message: msg,
                      isMe: msg.userId == currentUserId,
                    ),
                    const SizedBox(height: 8),
                  ],
                const SizedBox(height: 12),
              ],
            ),
          ),

          // ── Chat Input Bar ──
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
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
                        controller: _messageController,
                        // The column's CHECK is 500 characters.
                        inputFormatters: [LengthLimitingTextInputFormatter(500)],
                        style: TextStyle(color: p.ink, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Message room buddies…',
                          hintStyle:
                              TextStyle(color: p.ink3, fontSize: 14),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _sendMessage,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: p.primary,
                        shape: BoxShape.circle,
                        boxShadow: p.glow,
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
      ),
    );
  }
}

class _ChatMessageBubble extends StatelessWidget {
  const _ChatMessageBubble({
    required this.message,
    required this.isMe,
  });

  final RoomMessage message;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    // Server timestamps parse as UTC; showing .hour directly put every message
    // 5½ hours off in India.
    final t = message.createdAt.toLocal();
    final timeStr =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Opacity(
        opacity: message.pending ? 0.6 : 1,
        child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? p.primary : p.card2,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isMe && message.senderName != null) ...[
              Text(
                message.senderName!,
                style: TextStyle(
                  color: p.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
            ],
            Text(
              message.body,
              style: TextStyle(
                color: isMe ? Colors.white : p.ink,
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              message.pending ? 'Sending…' : timeStr,
              style: TextStyle(
                color: isMe
                    ? Colors.white.withValues(alpha: 0.7)
                    : p.ink3,
                fontSize: 10,
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}
