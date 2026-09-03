// Flutter has its own `MaterialType` (for the `Material` widget); hiding it lets
// the app's material-source enum keep the unprefixed name here.
import 'package:flutter/material.dart' hide MaterialType;
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/stores.dart';
import '../theme/app_theme.dart';
import 'common.dart';
import 'data_states.dart';

/// Opens [GenerateSheet] and reports whether something was generated.
///
/// [S] is the store that owns the generation — [QuizStore] or [FlashcardStore].
/// The sheet reads its `busy` and `error` straight off that store, so the
/// button's progress state and the failure notice both come from the same place
/// the write does.
Future<bool> showGenerateSheet<S extends AsyncStore>(
  BuildContext context, {
  required String title,
  required String subtitle,
  required String actionLabel,
  required String unit,
  required List<int> counts,
  required Future<bool> Function(S store, String materialId, int count)
      onGenerate,
}) async {
  final done = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.p.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (_) => GenerateSheet<S>(
      title: title,
      subtitle: subtitle,
      actionLabel: actionLabel,
      unit: unit,
      counts: counts,
      onGenerate: onGenerate,
    ),
  );
  return done ?? false;
}

/// Pick one uploaded file, pick how much to make, generate.
///
/// Shared by the Quiz and Cards tabs because the choice is the same in both: the
/// generators work from a single material's chunks, not from a search across
/// everything (see `supabase/functions/_shared/material.ts`).
///
/// Only materials that finished ingesting are offered. An unembedded file has no
/// `material_chunks` rows, so the function would refuse it — listing it would be
/// offering a button that can only fail.
class GenerateSheet<S extends AsyncStore> extends StatefulWidget {
  const GenerateSheet({
    super.key,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.unit,
    required this.counts,
    required this.onGenerate,
  });

  final String title;
  final String subtitle;

  /// Label on the generate button, e.g. "Generate quiz".
  final String actionLabel;

  /// What the counts count — "questions", "cards".
  final String unit;

  /// The sizes offered, smallest first. The middle one is preselected.
  final List<int> counts;

  final Future<bool> Function(S store, String materialId, int count) onGenerate;

  @override
  State<GenerateSheet<S>> createState() => _GenerateSheetState<S>();
}

class _GenerateSheetState<S extends AsyncStore>
    extends State<GenerateSheet<S>> {
  String? _materialId;
  late int _count;

  @override
  void initState() {
    super.initState();
    _count = widget.counts[widget.counts.length ~/ 2];

    // The Quiz and Cards tabs never had a reason to read the material list, so
    // this is usually its first load in the session. Post-frame because the
    // store notifies its listeners synchronously.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final store = context.read<OnboardingStore>();
      if (!store.loaded && !store.loading) store.load();
    });
  }

  Future<void> _generate() async {
    final materialId = _materialId;
    if (materialId == null) return;

    final store = context.read<S>();
    final ok = await widget.onGenerate(store, materialId, _count);
    if (!mounted) return;
    // On failure the sheet stays open with the store's error in it, so the
    // student can pick a different file without starting over.
    if (ok) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final materials = context.watch<OnboardingStore>();
    final store = context.watch<S>();

    final ready = materials.uploaded
        .where((m) => m.status == IngestStatus.embedded)
        .toList();
    final hidden = materials.uploaded.length - ready.length;

    // A file removed in another tab while this was open would leave a selection
    // pointing at nothing.
    final selected =
        ready.any((m) => m.id == _materialId) ? _materialId : null;

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
                        Text(widget.title,
                            style: TextStyle(
                                color: p.ink,
                                fontSize: 18,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 3),
                        Text(widget.subtitle,
                            style: TextStyle(color: p.ink3, fontSize: 12.5)),
                      ],
                    ),
                  ),
                  RoundIconButton(Symbols.close,
                      onTap: store.busy
                          ? null
                          : () => Navigator.of(context).maybePop()),
                ],
              ),

              if (store.error != null) ...[
                const SizedBox(height: 12),
                ErrorNotice(
                  message: store.error!,
                  onRetry: () => context.read<S>().clearError(),
                ),
              ],

              const SizedBox(height: 14),
              if (materials.loading && ready.isEmpty)
                const LoadingBlock(height: 90)
              else if (ready.isEmpty)
                _NothingReady(hasFiles: materials.uploaded.isNotEmpty)
              else
                Flexible(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    children: [
                      for (final material in ready)
                        _PickTile(
                          material: material,
                          selected: material.id == selected,
                          onTap: store.busy
                              ? null
                              : () =>
                                  setState(() => _materialId = material.id),
                        ),
                    ],
                  ),
                ),

              // Only worth saying when there is something to hide it from —
              // "nothing is ready" already covers the empty case above.
              if (hidden > 0 && ready.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Symbols.info, color: p.amber, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                          hidden == 1
                              ? "One more file isn't readable yet, so it isn't "
                                  'listed.'
                              : "$hidden more files aren't readable yet, so "
                                  "they aren't listed.",
                          style: TextStyle(
                              color: p.ink2, fontSize: 12, height: 1.45)),
                    ),
                  ],
                ),
              ],

              if (ready.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text('How many ${widget.unit}?',
                    style: TextStyle(
                        color: p.ink2,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final count in widget.counts)
                      SoftChip(
                        '$count',
                        tone: count == _count
                            ? ChipTone.primary
                            : ChipTone.neutral,
                        onTap: store.busy
                            ? null
                            : () => setState(() => _count = count),
                      ),
                  ],
                ),
              ],

              const SizedBox(height: 16),
              PillButton(
                store.busy ? 'Working on it…' : widget.actionLabel,
                icon: store.busy ? null : Symbols.auto_awesome,
                variant: selected == null || store.busy
                    ? PillVariant.outline
                    : PillVariant.primary,
                onTap: selected == null || store.busy ? null : _generate,
              ),
              const SizedBox(height: 8),
              // Named because the wait is real: one Gemini call writes the whole
              // set, and the server gives it up to a minute (D-015).
              Text('Written from that file only · can take up to a minute',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.ink3, fontSize: 11.5)),
            ],
          ),
        ),
      ),
    );
  }
}

/// One selectable file. Deliberately not [MaterialTile]: that row carries retry
/// and remove actions, and a picker is the wrong place to delete from.
class _PickTile extends StatelessWidget {
  const _PickTile({
    required this.material,
    required this.selected,
    this.onTap,
  });

  final StudyMaterial material;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        color: selected ? p.primarySoft : null,
        onTap: onTap,
        child: Row(
          children: [
            IconTile(Symbols.description,
                bg: selected ? p.primary.withValues(alpha: 0.16) : p.card2,
                fg: selected ? p.primary : p.ink3,
                size: 40,
                radius: 12),
            const SizedBox(width: 12),
            Expanded(
              child: Text(material.displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.ink, fontSize: 14, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 8),
            Icon(
              selected ? Symbols.check_circle : Symbols.radio_button_unchecked,
              color: selected ? p.primary : p.ink3,
              fill: selected ? 1 : 0,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when nothing can be generated from yet. The two reasons need different
/// advice, so they get different text.
class _NothingReady extends StatelessWidget {
  const _NothingReady({required this.hasFiles});

  final bool hasFiles;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: Column(
        children: [
          Icon(hasFiles ? Symbols.hourglass_top : Symbols.folder_open,
              color: p.ink3, size: 34),
          const SizedBox(height: 10),
          Text(hasFiles ? 'Nothing readable yet' : 'Nothing uploaded yet',
              style: TextStyle(
                  color: p.ink, fontSize: 14.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
              hasFiles
                  ? 'Your files are still being read, or they failed. Open the '
                      'Chat tab’s materials button to retry them.'
                  : 'Upload your syllabus or notes from the Chat tab, then '
                      'come back here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: p.ink3, fontSize: 12.5, height: 1.45)),
        ],
      ),
    );
  }
}
