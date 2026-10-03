import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/stores.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/data_states.dart';
import '../widgets/nav.dart';
import 'study_room_screen.dart';

/// Study buddies — browse active study rooms, join by code, create rooms,
/// and view classmates in your cohort.
class BuddyRoomScreen extends StatefulWidget {
  const BuddyRoomScreen({super.key, this.onBack});

  final VoidCallback? onBack;

  @override
  State<BuddyRoomScreen> createState() => _BuddyRoomScreenState();
}

class _BuddyRoomScreenState extends State<BuddyRoomScreen> {
  final _codeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final profiles = context.read<ProfileStore>();
      if (!profiles.loaded) profiles.load();
      final game = context.read<GamificationStore>();
      if (!game.loaded) game.load();
      final rooms = context.read<RoomStore>();
      rooms.loadLobby(classId: profiles.profile?.classId);
    });
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _refresh() async {
    final profiles = context.read<ProfileStore>();
    await profiles.load();
    if (!mounted) return;
    await context.read<GamificationStore>().load();
    if (!mounted) return;
    await context.read<RoomStore>().loadLobby(classId: profiles.profile?.classId);
  }

  /// Pushes the room screen for the room the store has already entered.
  void _openRoom(StudyRoom room) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StudyRoomScreen(
          onLeave: () {
            context.read<RoomStore>().loadLobby(
                classId: context.read<ProfileStore>().profile?.classId);
          },
        ),
      ),
    );
  }

  /// Joins via 6-character invite code.
  Future<void> _joinByCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      _toast('Enter a 6-letter room code');
      return;
    }
    FocusScope.of(context).unfocus();

    final store = context.read<RoomStore>();
    final room = await store.joinByCode(code);
    if (!mounted) return;

    if (room != null) {
      _codeController.clear();
      _openRoom(room);
    } else {
      _toast(store.error ?? 'Invalid room code or room is full.');
    }
  }

  /// A lobby tile's Join goes through the same RPC as a typed code: entering
  /// without joining would leave the student unable to read or send chat.
  Future<void> _joinFromLobby(StudyRoom room) async {
    final store = context.read<RoomStore>();
    final joined = await store.joinByCode(room.inviteCode);
    if (!mounted) return;
    if (joined != null) {
      _openRoom(joined);
    } else {
      _toast(store.error ?? 'Could not join that room.');
      store.loadLobby(classId: context.read<ProfileStore>().profile?.classId);
    }
  }

  /// Asks for a name and how many people; the timer is set inside the room.
  Future<void> _showCreateRoomSheet() async {
    final p = context.p;
    final nameController = TextEditingController(text: 'Study Session');
    int maxMembers = 4;
    String? sheetError;

    final created = await showModalBottomSheet<StudyRoom>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: p.line2,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Create Study Room',
                style: TextStyle(
                  color: p.ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Focus with classmates using a synchronized timer and live chat.',
                style: TextStyle(color: p.ink2, fontSize: 13.5),
              ),
              const SizedBox(height: 18),

              // Room Name
              Text('Room Name',
                  style: TextStyle(
                      color: p.ink2,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: p.card2,
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: TextField(
                  controller: nameController,
                  style: TextStyle(color: p.ink, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'e.g. DSA Grind Session',
                    hintStyle: TextStyle(color: p.ink3, fontSize: 14),
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Room size. Focus and break lengths are set inside the room.
              Text('How many people?',
                  style: TextStyle(
                      color: p.ink2,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text('Including you. Up to 6 in a room.',
                  style: TextStyle(color: p.ink3, fontSize: 12)),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final n in RoomStore.roomSizes) ...[
                    Expanded(
                      child: GestureDetector(
                        key: ValueKey('room-size-$n'),
                        onTap: () => setModalState(() => maxMembers = n),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: maxMembers == n ? p.primary : p.card2,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '$n',
                            style: TextStyle(
                              color: maxMembers == n ? Colors.white : p.ink2,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (n != RoomStore.roomSizes.last) const SizedBox(width: 8),
                  ],
                ],
              ),
              const SizedBox(height: 22),

              if (sheetError != null) ...[
                Text(sheetError!,
                    style: TextStyle(
                        color: p.error,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
              ],
              PillButton(
                'Create & Enter Room',
                icon: Symbols.groups,
                onTap: () async {
                  final name = nameController.text.trim();
                  if (name.isEmpty) {
                    setModalState(() => sheetError = 'Give the room a name.');
                    return;
                  }

                  final store = sheetCtx.read<RoomStore>();
                  final classId =
                      sheetCtx.read<ProfileStore>().profile?.classId;

                  final room = await store.createRoom(
                    name: name,
                    classId: classId,
                    maxMembers: maxMembers,
                  );

                  if (!sheetCtx.mounted) return;
                  if (room != null) {
                    Navigator.of(sheetCtx).pop(room);
                  } else {
                    setModalState(() => sheetError =
                        store.error ?? 'Could not create the room.');
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );

    if (created != null && mounted) {
      _openRoom(created);
    }
  }

  Future<void> _joinClass() async {
    final store = context.read<ProfileStore>();
    if (store.classes.isEmpty) await store.loadClasses();
    if (!mounted) return;

    if (store.classes.isEmpty) {
      _toast('No classes are set up yet.');
      return;
    }

    final p = context.p;
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Text('Pick your class',
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
              ),
              for (final c in store.classes)
                ListTile(
                  leading: Icon(Symbols.groups, color: p.primary),
                  title: Text((c['name'] as String?) ?? 'Class',
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600)),
                  onTap: () => Navigator.of(sheetContext).pop(c['id'] as String),
                ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;

    final ok = await store.joinClass(picked);
    if (!mounted) return;
    if (!ok) {
      _toast(store.error ?? 'Could not join that class');
      return;
    }
    await _refresh();
  }

  Future<void> _leaveClass() async {
    final p = context.p;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: p.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Leave this class?',
            style: TextStyle(
                color: p.ink, fontSize: 18, fontWeight: FontWeight.w800)),
        content: Text(
            'You’ll drop off the class leaderboard. Your streak, XP and badges '
            'stay with you.',
            style: TextStyle(color: p.ink2, fontSize: 14, height: 1.45)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Cancel', style: TextStyle(color: p.ink2)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Leave',
                style: TextStyle(color: p.error, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final store = context.read<ProfileStore>();
    final ok = await store.leaveClass();
    if (!mounted) return;
    if (!ok) {
      _toast(store.error ?? 'Could not leave the class');
      return;
    }
    await _refresh();
  }

  String _thousands(int n) =>
      n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final profiles = context.watch<ProfileStore>();
    final game = context.watch<GamificationStore>();
    final roomStore = context.watch<RoomStore>();

    final joined = profiles.profile?.classId != null;
    final members = game.leaderboard;
    final activeRooms = roomStore.activeRooms;

    return Scaffold(
      backgroundColor: p.bg,
      body: Column(
        children: [
          const TopInset(),

          // ── App Bar ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                RoundIconButton(Symbols.arrow_back, onTap: widget.onBack),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Study Buddy Rooms',
                        style: TextStyle(
                          color: p.ink,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Focus with classmates in real-time',
                        style: TextStyle(color: p.ink3, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                // Create room button
                RoundIconButton(
                  Symbols.add,
                  plain: false,
                  color: p.primary,
                  onTap: _showCreateRoomSheet,
                ),
              ],
            ),
          ),

          Expanded(
            child: RefreshIndicator(
              color: p.primary,
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  // ── Join by Code Card ──
                  AppCard(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Icon(Symbols.key, color: p.primary, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _codeController,
                            textCapitalization: TextCapitalization.characters,
                            style: TextStyle(
                              color: p.ink,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Enter 6-letter room code…',
                              hintStyle: TextStyle(
                                color: p.ink3,
                                fontSize: 13,
                                fontWeight: FontWeight.normal,
                                letterSpacing: 0,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                            ),
                            onSubmitted: (_) => _joinByCode(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        PillButton(
                          'Join',
                          expand: false,
                          onTap: _joinByCode,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Live Study Rooms Header ──
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Row(
                          children: [
                            Icon(Symbols.sensors, size: 20, color: p.green),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Active Study Rooms',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: p.ink,
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (activeRooms.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: p.greenSoft,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            '${activeRooms.length} live',
                            style: TextStyle(
                              color: p.green,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // ── Rooms List or Empty State ──
                  if (roomStore.error != null && !roomStore.busy) ...[
                    ErrorNotice(
                      message: roomStore.error!,
                      onRetry: () => roomStore.loadLobby(
                          classId: profiles.profile?.classId),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (roomStore.loading && activeRooms.isEmpty)
                    const LoadingBlock(height: 96)
                  else if (activeRooms.isEmpty)
                    AppCard(
                      color: p.card2.withValues(alpha: 0.5),
                      shadow: false,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 20),
                      child: Column(
                        children: [
                          Icon(Symbols.door_open,
                              size: 36, color: p.primary.withValues(alpha: 0.7)),
                          const SizedBox(height: 8),
                          Text(
                            'No study rooms open right now',
                            style: TextStyle(
                              color: p.ink,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Start a room and invite your classmates to focus together!',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: p.ink3, fontSize: 12.5),
                          ),
                          const SizedBox(height: 14),
                          PillButton(
                            '+ Start a Study Room',
                            expand: false,
                            onTap: _showCreateRoomSheet,
                          ),
                        ],
                      ),
                    )
                  else
                    for (final r in activeRooms) ...[
                      _RoomTile(
                        room: r,
                        onJoin: roomStore.busy ? null : () => _joinFromLobby(r),
                      ),
                      const SizedBox(height: 10),
                    ],

                  const SizedBox(height: 24),

                  // ── Class Cohort Section ──
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Row(
                          children: [
                            Icon(Symbols.school, size: 20, color: p.primary),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Your Class Cohort',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: p.ink,
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (joined)
                        TextButton(
                          onPressed: profiles.busy ? null : _leaveClass,
                          child: Text(
                            'Leave Class',
                            style: TextStyle(
                              color: p.error,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  if (!joined)
                    EmptyState(
                      icon: Symbols.groups,
                      title: 'You haven’t joined a class yet',
                      message:
                          'Join your college class to see cohort rankings and rooms.',
                      actionLabel: 'Join a class',
                      onAction: profiles.busy ? null : _joinClass,
                    )
                  else ...[
                    _ClassCard(
                      name: profiles.className ?? 'Your class',
                      memberCount: members.length,
                      myRank: game.myRank,
                    ),
                    const SizedBox(height: 16),
                    CardHeader('Classmates',
                        action: game.loading && !game.loaded
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    color: p.ink3, strokeWidth: 2),
                              )
                            : null),
                    if (game.loading && !game.loaded)
                      const LoadingBlock(height: 120)
                    else if (members.isEmpty)
                      EmptyState(
                        icon: Symbols.person_add,
                        title: 'Nobody else here yet',
                        message:
                            'You’re the first from this class on StudyTrail. '
                            'Classmates show up as soon as they join.',
                      )
                    else
                      AppCard(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          children: [
                            for (final entry in members)
                              _MemberRow(
                                entry: entry,
                                xpLabel: '${_thousands(entry.totalXp)} XP',
                              ),
                          ],
                        ),
                      ),
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

class _RoomTile extends StatelessWidget {
  const _RoomTile({required this.room, required this.onJoin});

  final StudyRoom room;
  final VoidCallback? onJoin;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: p.primarySoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Symbols.timer, color: p.primary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  room.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: p.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 10,
                  runSpacing: 2,
                  children: [
                    Text(
                      '🍅 ${room.timerDurationMin}m focus',
                      style: TextStyle(color: p.ink3, fontSize: 12),
                    ),
                    Text(
                      '👥 ${room.memberCount}/${room.maxMembers}',
                      style: TextStyle(color: p.ink3, fontSize: 12),
                    ),
                    Text(
                      'Code: ${room.inviteCode}',
                      style: TextStyle(
                        color: p.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          PillButton(
            room.isFull ? 'Full' : 'Join',
            expand: false,
            onTap: room.isFull ? null : onJoin,
          ),
        ],
      ),
    );
  }
}

class _ClassCard extends StatelessWidget {
  const _ClassCard({
    required this.name,
    required this.memberCount,
    required this.myRank,
  });

  final String name;
  final int memberCount;
  final LeaderboardEntry? myRank;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final rank = myRank;

    return AppCard(
      gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [p.primary, p.primary2]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Symbols.groups,
                  color: Colors.white.withValues(alpha: 0.9), size: 20),
              const SizedBox(width: 8),
              Text('YOUR CLASS',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 12,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 12),
          Text(name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5)),
          const SizedBox(height: 16),
          Row(
            children: [
              _Stat('$memberCount', 'On StudyTrail'),
              _Stat(rank == null ? '—' : '#${rank.rank}', 'Your rank'),
              _Stat(rank == null ? '—' : 'Lv ${rank.level}', 'Your level'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);
  final String value, label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800)),
          Text(label,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8), fontSize: 11.5)),
        ],
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.entry, required this.xpLabel});

  final LeaderboardEntry entry;
  final String xpLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final me = entry.isMe;

    final trophyColor = switch (entry.rank) {
      1 => p.amber,
      2 => p.ink3,
      3 => p.coral,
      _ => null,
    };

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: me ? p.primarySoft : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: trophyColor != null
                ? Icon(Symbols.trophy, color: trophyColor, size: 24, fill: 1)
                : Text('${entry.rank}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: p.ink2,
                        fontSize: 15,
                        fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 8),
          GradAvatar(entry.initial, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(me ? '${entry.fullName} (You)' : entry.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 14.5,
                        fontWeight: me ? FontWeight.w800 : FontWeight.w700)),
                Text('Level ${entry.level}',
                    style: TextStyle(color: p.ink3, fontSize: 11.5)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(xpLabel,
              style: TextStyle(
                  color: me ? p.primary : p.ink2,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
