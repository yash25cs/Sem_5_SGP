// Flutter has its own `MaterialType` (for the `Material` widget); hiding it lets
// the app's material-source enum keep the unprefixed name here.
import 'package:flutter/material.dart' hide MaterialType;
import 'package:material_symbols_icons/symbols.dart';

import '../models/models.dart';
import '../state/stores.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// A YouTube playlist in the library: one row however many videos it holds
/// (D-038), with its reading progress, and its videos underneath on demand.
///
/// Shared by onboarding's upload step and the chat screen's materials sheet,
/// which build the video rows themselves through [videoBuilder] — each wires
/// retry, remove and summarize its own way.
class PlaylistTile extends StatefulWidget {
  const PlaylistTile({
    super.key,
    required this.playlist,
    required this.progress,
    required this.videos,
    required this.videoBuilder,
    this.reading = false,
    this.onResume,
    this.onRetryFailed,
    this.onRemove,
  });

  final MaterialPlaylist playlist;
  final PlaylistProgress progress;

  /// The stored videos, in playlist order.
  final List<StudyMaterial> videos;
  final Widget Function(StudyMaterial video) videoBuilder;

  /// This playlist's videos are being read right now.
  final bool reading;

  /// Shown while videos are left and nothing is reading them.
  final VoidCallback? onResume;

  /// Shown while some videos failed and this playlist isn't being read.
  final VoidCallback? onRetryFailed;
  final VoidCallback? onRemove;

  @override
  State<PlaylistTile> createState() => _PlaylistTileState();
}

class _PlaylistTileState extends State<PlaylistTile> {
  bool _open = false;

  /// Asked first: a whole course goes, and reading it again takes minutes.
  Future<void> _confirmRemove() async {
    final p = context.p;
    final count = widget.videos.length;
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: p.card,
        title: Text('Remove this playlist?',
            style: TextStyle(color: p.ink, fontWeight: FontWeight.w800)),
        content: Text(
            '"${widget.playlist.title}" and its $count video'
            '${count == 1 ? '' : 's'} will be removed, with everything the AI '
            'read from them.',
            style: TextStyle(color: p.ink2, height: 1.45)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Cancel', style: TextStyle(color: p.ink3)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Remove',
                style: TextStyle(color: p.error, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (yes == true && mounted) widget.onRemove?.call();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final progress = widget.progress;
    final waiting = progress.pending > 0 && !widget.reading;
    final done = progress.pending == 0;
    final ofTotal = '${progress.ready} of ${progress.total}';

    final (color, tone, label) = widget.reading
        ? (p.amber, ChipTone.amber, 'Reading · $ofTotal ready')
        : waiting
            ? (p.ink3, ChipTone.neutral, 'Paused · $ofTotal ready')
            : progress.ready == progress.total
                ? (p.green, ChipTone.green, '${progress.total} videos ready')
                : (p.green, ChipTone.green, '$ofTotal ready');

    final notes = [
      if (progress.skipped > 0)
        '${progress.skipped} skipped — no captions or unavailable',
      if (progress.failed > 0) '${progress.failed} need a retry',
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            onTap: () => setState(() => _open = !_open),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconTile(Symbols.playlist_play,
                        bg: color.withValues(alpha: 0.14),
                        fg: color,
                        size: 40,
                        radius: 12),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.playlist.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: p.ink,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              SoftChip(label, tone: tone, small: true),
                              if (waiting && widget.onResume != null)
                                SoftChip('Resume',
                                    icon: Symbols.play_arrow,
                                    tone: ChipTone.primary,
                                    small: true,
                                    onTap: widget.onResume),
                              if (progress.failed > 0 &&
                                  !widget.reading &&
                                  widget.onRetryFailed != null)
                                SoftChip('Retry ${progress.failed}',
                                    icon: Symbols.refresh,
                                    tone: ChipTone.primary,
                                    small: true,
                                    onTap: widget.onRetryFailed),
                            ],
                          ),
                        ],
                      ),
                    ),
                    RoundIconButton(
                        _open ? Symbols.expand_less : Symbols.expand_more,
                        onTap: () => setState(() => _open = !_open)),
                    RoundIconButton(Symbols.close,
                        onTap: widget.onRemove == null ? null : _confirmRemove),
                  ],
                ),
                if (!done) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: progress.fraction,
                      minHeight: 5,
                      color: color,
                      backgroundColor: p.line,
                    ),
                  ),
                ],
                if (notes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(notes.join(' · '),
                      style: TextStyle(
                          color: p.ink3, fontSize: 11.5, height: 1.4)),
                ],
              ],
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.only(left: 14, top: 10),
              child: widget.videos.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text("Videos appear here as they're read.",
                          style: TextStyle(color: p.ink3, fontSize: 12.5)),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final video in widget.videos)
                          widget.videoBuilder(video),
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}
