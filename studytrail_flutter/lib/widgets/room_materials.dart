import 'package:flutter/material.dart' hide MaterialType;
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/stores.dart';
import '../theme/app_theme.dart';
import 'common.dart';
import 'expandable_item_card.dart';

/// Copies [share] into the student's library, with the library limit checked
/// first and the library re-read afterwards. Shows its own snackbar; returns
/// true when the copy landed.
Future<bool> saveSharedToLibrary(
    BuildContext context, RoomSharedMaterial share) async {
  final messenger = ScaffoldMessenger.of(context);
  final library = context.read<OnboardingStore>();
  final rooms = context.read<RoomStore>();
  if (!library.loaded) await library.load();
  if (library.atLimit) {
    messenger.showSnackBar(const SnackBar(
        content: Text('Your library is full '
            '(${OnboardingStore.maxMaterials} items). '
            'Remove one to save this.')));
    return false;
  }
  final copy = await rooms.saveShared(share);
  if (copy == null) {
    messenger.showSnackBar(SnackBar(
        content: Text(rooms.error ?? "Couldn't save that. Try again.")));
    return false;
  }
  library.load().ignore();
  messenger.showSnackBar(SnackBar(
      content: Text('“${copy.displayName}” is in your library — '
          'ready for quizzes, flashcards and chat.')));
  return true;
}

/// One shared material: what it is, who shared it and when, with Save (or
/// "In library") and, for the sharer or host, Remove.
class SharedMaterialTile extends StatelessWidget {
  const SharedMaterialTile({
    super.key,
    required this.share,
    required this.saving,
    required this.onSave,
    this.onRemove,
    this.mine = false,
  });

  final RoomSharedMaterial share;
  final bool saving;
  final VoidCallback? onSave;
  final VoidCallback? onRemove;

  /// Shared by this student: it's already theirs, so no Save.
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final who = mine ? 'You' : share.sharedByName.split(' ').first;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          IconTile(
            share.isVideo ? Symbols.smart_display : Symbols.description,
            bg: share.isVideo ? p.coralSoft : p.primarySoft,
            fg: share.isVideo ? p.coralInk : p.primary,
            size: 40,
            radius: 12,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(share.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('$who · ${whenLabel(share.createdAt, DateTime.now())}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.ink3, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (saving)
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2.4, color: p.primary),
            )
          else if (share.saved || mine)
            Tag(mine ? 'Yours' : 'In library',
                bg: p.greenSoft, fg: p.green)
          else
            PillButton('Save',
                icon: Symbols.download, expand: false, onTap: onSave),
          if (onRemove != null)
            IconButton(
              tooltip: 'Remove from room',
              onPressed: onRemove,
              icon: Icon(Symbols.close, color: p.ink3, size: 20),
            ),
        ],
      ),
    );
  }
}

/// "Shared materials" inside a room: members share files from their library,
/// and anyone in the room can save a copy to theirs.
class RoomMaterialsCard extends StatelessWidget {
  const RoomMaterialsCard({super.key});

  Future<void> _share(BuildContext context) async {
    final library = context.read<OnboardingStore>();
    if (!library.loaded) await library.load();
    if (!context.mounted) return;
    final rooms = context.read<RoomStore>();
    final shared = {for (final s in rooms.sharedMaterials) s.materialId};
    final choices = [
      for (final m in library.uploaded)
        if (m.isReady && !shared.contains(m.id)) m,
    ];

    final p = context.p;
    final picked = await showModalBottomSheet<StudyMaterial>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetCtx) => ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetCtx).size.height * 0.75),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Share a material',
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 20,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('Everyone in the room can save a copy to their library.',
                  style: TextStyle(color: p.ink2, fontSize: 13.5)),
              const SizedBox(height: 14),
              if (choices.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    library.uploaded.isEmpty
                        ? 'Your library is empty. Upload notes first, '
                            'then share them here.'
                        : 'Everything ready in your library is already '
                            'shared here.',
                    style: TextStyle(color: p.ink3, fontSize: 13.5),
                  ),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final m in choices)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                              m.sourceType == MaterialType.videoLink
                                  ? Symbols.smart_display
                                  : Symbols.description,
                              color: p.primary),
                          title: Text(m.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: p.ink,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700)),
                          trailing:
                              Icon(Symbols.ios_share, color: p.ink3, size: 20),
                          onTap: () => Navigator.of(sheetCtx).pop(m),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    final ok = await rooms.shareMaterial(picked);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok
            ? 'Shared “${picked.displayName}” with the room.'
            : rooms.error ?? "Couldn't share that. Try again.")));
  }

  Future<void> _remove(BuildContext context, RoomSharedMaterial share) async {
    final sure = await confirmDelete(
      context,
      title: 'Remove from room?',
      message: '“${share.title}” will no longer be shared here. Copies '
          'people already saved stay in their libraries.',
    );
    if (!sure || !context.mounted) return;
    final rooms = context.read<RoomStore>();
    final ok = await rooms.unshareMaterial(share);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(rooms.error ?? "Couldn't remove that.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final rooms = context.watch<RoomStore>();
    final shared = rooms.sharedMaterials;
    final me = rooms.myUserId;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Symbols.folder_shared, size: 20, color: p.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Shared materials (${shared.length})',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w800)),
              ),
              PillButton('Share',
                  icon: Symbols.add,
                  expand: false,
                  onTap: rooms.busy ? null : () => _share(context)),
            ],
          ),
          const SizedBox(height: 12),
          if (shared.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'Nothing shared yet. Share notes from your library and '
                'everyone here can save them.',
                style: TextStyle(color: p.ink3, fontSize: 12.5),
              ),
            )
          else
            for (final s in shared)
              SharedMaterialTile(
                share: s,
                mine: s.sharedBy == me,
                saving: rooms.isSaving(s.id),
                onSave: () => saveSharedToLibrary(context, s),
                onRemove: rooms.canUnshare(s) && !rooms.busy
                    ? () => _remove(context, s)
                    : null,
              ),
        ],
      ),
    );
  }
}

/// A past (or current) room: when the student was in it, what was shared
/// there — still saveable — and the group quizzes they finished there.
Future<void> showRoomHistorySheet(
  BuildContext context,
  RoomHistoryEntry entry, {
  VoidCallback? onRejoin,
}) {
  final p = context.p;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _RoomHistorySheet(entry: entry, onRejoin: onRejoin),
  );
}

class _RoomHistorySheet extends StatefulWidget {
  const _RoomHistorySheet({required this.entry, this.onRejoin});

  final RoomHistoryEntry entry;
  final VoidCallback? onRejoin;

  @override
  State<_RoomHistorySheet> createState() => _RoomHistorySheetState();
}

class _RoomHistorySheetState extends State<_RoomHistorySheet> {
  List<RoomSharedMaterial>? _materials;
  List<RoomQuizResult>? _quizzes;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final detail =
          await context.read<RoomStore>().loadHistoryDetail(widget.entry.roomId);
      if (!mounted) return;
      setState(() {
        _materials = detail.materials;
        _quizzes = detail.quizzes;
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't load this room.");
    }
  }

  Future<void> _save(RoomSharedMaterial share) async {
    final ok = await saveSharedToLibrary(context, share);
    if (ok && mounted) {
      setState(() => _materials = [
            for (final m in _materials ?? const <RoomSharedMaterial>[])
              m.id == share.id ? m.asSaved() : m,
          ]);
    }
  }

  Future<void> _removeFromHistory() async {
    final sure = await confirmDelete(
      context,
      title: 'Remove from history?',
      message: '“${widget.entry.name}” will be taken out of your room '
          'history, along with access to what was shared there. Materials '
          'you saved stay in your library.',
    );
    if (!sure || !mounted) return;
    final rooms = context.read<RoomStore>();
    final ok = await rooms.removeFromHistory(widget.entry.roomId);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(rooms.error ?? "Couldn't remove that.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final e = widget.entry;
    final rooms = context.watch<RoomStore>();
    final now = DateTime.now();
    final me = rooms.myUserId;

    Widget section(String title) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 10),
          child: Text(title,
              style: TextStyle(
                  color: p.ink, fontSize: 15, fontWeight: FontWeight.w800)),
        );
    Widget note(String text) => Text(text,
        style: TextStyle(color: p.ink3, fontSize: 12.5));

    return ConstrainedBox(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(e.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 20,
                        fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 8),
              e.isActive
                  ? Tag('Live', bg: p.greenSoft, fg: p.green)
                  : Tag('Closed', bg: p.card2, fg: p.ink3),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${e.isHost ? 'You created this room' : 'You joined'} · '
            '${whenLabel(e.firstJoinedAt, now)}',
            style: TextStyle(color: p.ink2, fontSize: 13),
          ),
          if (e.leftAt != null && !e.isMember)
            Text('Left ${whenLabel(e.leftAt!, now)}',
                style: TextStyle(color: p.ink3, fontSize: 12.5)),
          if (e.isActive && widget.onRejoin != null) ...[
            const SizedBox(height: 14),
            PillButton(e.isMember ? 'Back to room' : 'Rejoin room',
                icon: Symbols.login,
                onTap: () {
                  Navigator.of(context).pop();
                  widget.onRejoin!();
                }),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            note(_error!),
          ] else if (_materials == null) ...[
            const SizedBox(height: 24),
            Center(child: CircularProgressIndicator(color: p.primary)),
          ] else ...[
            section('Shared materials (${_materials!.length})'),
            if (_materials!.isEmpty)
              note('Nothing was shared in this room.')
            else
              for (final s in _materials!)
                SharedMaterialTile(
                  share: s,
                  mine: s.sharedBy == me,
                  saving: rooms.isSaving(s.id),
                  onSave: () => _save(s),
                ),
            section('Group quizzes (${_quizzes!.length})'),
            if (_quizzes!.isEmpty)
              note('You didn\'t finish a group quiz here.')
            else
              for (final q in _quizzes!) _QuizResultRow(result: q, now: now),
          ],
          const SizedBox(height: 20),
          PillButton('Remove from history',
              icon: Symbols.delete,
              variant: PillVariant.danger,
              onTap: rooms.busy ? null : _removeFromHistory),
        ],
      ),
    );
  }
}

class _QuizResultRow extends StatelessWidget {
  const _QuizResultRow({required this.result, required this.now});

  final RoomQuizResult result;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final r = result;
    final score = r.score == null
        ? 'Not handed in'
        : r.speed
            ? '${r.score} pts'
            : '${r.score}/${r.questionCount}';
    final rank = r.rank == null ? '' : ' · #${r.rank} of ${r.players}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          IconTile(r.speed ? Symbols.bolt : Symbols.groups,
              bg: p.amberSoft, fg: p.onAmber, size: 40, radius: 12),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
                Text('${whenLabel(r.finishedAt, now)}$rank',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.ink3, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Tag(score, bg: p.primarySoft, fg: p.primary),
        ],
      ),
    );
  }
}
