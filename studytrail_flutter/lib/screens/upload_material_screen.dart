// Flutter has its own `MaterialType` (for the Material widget); hiding it lets
// the app's material-source enum keep the unprefixed name here.
import 'package:flutter/material.dart' hide MaterialType;
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/stores.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/data_states.dart';
import '../widgets/material_tile.dart';
import '../widgets/nav.dart';
import '../widgets/summary_sheet.dart';

/// Onboarding step 2 — pick a source type, then upload real files (or paste a
/// link). Files land in the private `materials` bucket + `materials` table, and
/// the `embed-material` function reads each one straight away, so the row's chip
/// moves Uploaded → Processing → Ready without leaving this screen.
class UploadMaterialScreen extends StatefulWidget {
  const UploadMaterialScreen({super.key, this.onNext, this.onBack});
  final VoidCallback? onNext;
  final VoidCallback? onBack;

  @override
  State<UploadMaterialScreen> createState() => _UploadMaterialScreenState();
}

class _UploadMaterialScreenState extends State<UploadMaterialScreen> {
  int _selected = 0;

  static const _opts = [
    (
      Symbols.description,
      'Syllabus PDF',
      'Course outline or exam blueprint',
      MaterialType.syllabusPdf
    ),
    (
      Symbols.edit_note,
      'My notes',
      'Handwritten or typed study notes',
      MaterialType.notes
    ),
    (
      Symbols.smart_display,
      'Video / playlist',
      'Lecture recordings or YouTube',
      MaterialType.videoLink
    ),
  ];

  MaterialType get _type => _opts[_selected].$4;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<OnboardingStore>().load();
    });
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _browse() async {
    final store = context.read<OnboardingStore>();
    final count = await store.pickAndUpload(_type);
    if (!mounted) return;

    final failure = store.error;
    if (failure != null) {
      // A non-zero count alongside an error means the batch stopped partway.
      // Say both halves — the file list below already shows what landed, and a
      // plain "3 files uploaded" would contradict it.
      _toast(count == 0 ? failure : '$count uploaded, then: $failure');
    } else if (count > 0) {
      _toast(count == 1 ? 'File uploaded' : '$count files uploaded');
    }
  }

  /// Retries a row that came back `failed` — a Gemini hiccup, a missing key, or
  /// a file it couldn't read.
  Future<void> _retry(StudyMaterial material) async {
    final store = context.read<OnboardingStore>();
    final ok = await store.reingest(material);
    if (!mounted) return;
    _toast(ok ? 'Reading it again…' : store.error ?? 'Could not read that file');
  }

  /// Video links have nothing to upload — they're recorded as a row so a later
  /// phase can fetch the transcript. Nothing reads them yet, which the sheet and
  /// the drop zone both say out loud.
  Future<void> _addLink() async {
    final controller = TextEditingController();
    final p = context.p;

    final url = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.of(sheetContext).viewInsets.bottom + 24),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add a video or article link',
                  style: TextStyle(
                      color: p.ink, fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.url,
                style: TextStyle(color: p.ink, fontSize: 14.5),
                onSubmitted: (v) => Navigator.of(sheetContext).pop(v.trim()),
                decoration: InputDecoration(
                  hintText: 'https://youtube.com/…',
                  hintStyle: TextStyle(color: p.ink3, fontSize: 14),
                  filled: true,
                  fillColor: p.card2,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: p.line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: p.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: p.primary, width: 1.6),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              PillButton('Add link',
                  icon: Symbols.link,
                  onTap: () =>
                      Navigator.of(sheetContext).pop(controller.text.trim())),
            ],
          ),
        ),
      ),
    );
    controller.dispose();

    if (url == null || url.isEmpty || !mounted) return;
    final store = context.read<OnboardingStore>();
    final ok = await store.addLink(url);
    _toast(ok ? 'Link added' : store.error ?? 'Could not add that link');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final store = context.watch<OnboardingStore>();
    final isLink = _type == MaterialType.videoLink;

    return Scaffold(
      backgroundColor: p.bg,
      body: Column(
        children: [
          const TopInset(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 20, 4),
            child: Row(
              children: [
                RoundIconButton(Symbols.arrow_back, onTap: widget.onBack),
                const Spacer(),
                Text('Step 2 of 3',
                    style: TextStyle(
                        color: p.ink3, fontSize: 13, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                Text('What should we learn from?',
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                        letterSpacing: -0.6)),
                const SizedBox(height: 8),
                Text('Add one or more sources. You can always add more later.',
                    style: TextStyle(color: p.ink2, fontSize: 14, height: 1.5)),
                const SizedBox(height: 22),

                if (store.error != null)
                  ErrorNotice(
                    message: store.error!,
                    onRetry: () => context.read<OnboardingStore>().clearError(),
                  ),

                for (var i = 0; i < _opts.length; i++) ...[
                  _OptionCard(
                    icon: _opts[i].$1,
                    title: _opts[i].$2,
                    subtitle: _opts[i].$3,
                    selected: _selected == i,
                    onTap: () => setState(() => _selected = i),
                  ),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 10),

                _DropZone(
                  isLink: isLink,
                  busy: store.busy,
                  // A link has nothing to store, so the file cap doesn't apply
                  // to it.
                  atLimit: !isLink && store.atLimit,
                  onTap: store.busy || (!isLink && store.atLimit)
                      ? null
                      : (isLink ? _addLink : _browse),
                ),

                if (isLink) ...[
                  const SizedBox(height: 10),
                  // Said here rather than discovered later: the row will sit on
                  // "Uploaded" forever, and that shouldn't look like a bug.
                  Row(
                    children: [
                      Icon(Symbols.info, color: p.ink3, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                            "Links are saved to your library, but the AI can't "
                            'read them yet — upload a PDF or a text file for '
                            'answers from your own material.',
                            style: TextStyle(
                                color: p.ink3, fontSize: 12, height: 1.45)),
                      ),
                    ],
                  ),
                ],

                if (store.uploaded.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  CardHeader('Added (${store.uploaded.length}'
                      ' of ${OnboardingStore.maxMaterials})'),
                  for (final material in store.uploaded)
                    MaterialTile(
                      material: material,
                      onRetry: store.busy ? null : () => _retry(material),
                      onRemove: store.busy
                          ? null
                          : () => context
                              .read<OnboardingStore>()
                              .removeMaterial(material),
                      onSummarize: () => SummarySheet.show(context,
                          materialId: material.id,
                          title: material.displayName),
                    ),
                ],
              ],
            ),
          ),
          FooterBar(
            child: PillButton(
                store.uploaded.isEmpty ? 'Skip for now' : 'Continue',
                trailingIcon: Symbols.arrow_forward,
                variant: store.uploaded.isEmpty
                    ? PillVariant.outline
                    : PillVariant.primary,
                onTap: store.busy ? null : widget.onNext),
          ),
        ],
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.selected,
      this.onTap});
  final IconData icon;
  final String title, subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? p.primarySoft : p.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? p.primary : p.line,
              width: selected ? 2 : 1.2),
          boxShadow: selected ? null : p.shadowSm,
        ),
        child: Row(
          children: [
            IconTile(icon,
                bg: selected ? p.primary : p.card2,
                fg: selected ? p.onPrimary : p.ink2,
                size: 46),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(color: p.ink2, fontSize: 12.5)),
                ],
              ),
            ),
            Icon(
                selected
                    ? Symbols.check_circle
                    : Symbols.radio_button_unchecked,
                color: selected ? p.primary : p.line2,
                fill: selected ? 1 : 0,
                size: 24),
          ],
        ),
      ),
    );
  }
}

class _DropZone extends StatelessWidget {
  const _DropZone({
    required this.isLink,
    required this.busy,
    this.atLimit = false,
    this.onTap,
  });

  final bool isLink;
  final bool busy;
  final bool atLimit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: DottedCard(
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                  color: p.primarySoft, shape: BoxShape.circle),
              child: busy
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: CircularProgressIndicator(
                          color: p.primary, strokeWidth: 2.6),
                    )
                  : Icon(isLink ? Symbols.link : Symbols.cloud_upload,
                      color: p.primary, size: 28),
            ),
            const SizedBox(height: 12),
            Text(
                busy
                    ? 'Uploading…'
                    : atLimit
                        ? 'File limit reached'
                        : isLink
                            ? 'Paste a video or article link'
                            : 'Tap to choose files',
                style: TextStyle(
                    color: p.ink, fontSize: 14.5, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
                atLimit && !isLink
                    ? 'Remove one below to add another'
                    : isLink
                        ? 'Saved for later — links are not read yet'
                        // 25 MB is the bucket's limit, not the reader's:
                        // `embed-material` refuses a PDF over 14 MB and a text
                        // file over 2 MB, so promising 25 would upload files
                        // that then fail to be read.
                        : 'PDF up to 14 MB · TXT or MD up to 2 MB',
                textAlign: TextAlign.center,
                style: TextStyle(color: p.ink3, fontSize: 12)),
            const SizedBox(height: 14),
            SoftChip(isLink ? 'Add link' : 'Browse files',
                icon: isLink ? Symbols.add_link : Symbols.folder_open,
                tone: ChipTone.primary,
                onTap: onTap),
          ],
        ),
      ),
    );
  }
}

/// Dashed-border upload container.
class DottedCard extends StatelessWidget {
  const DottedCard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return CustomPaint(
      painter: _DashedBorderPainter(color: p.line2, radius: 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 18),
        child: child,
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final rrect = RRect.fromRectAndRadius(
        Offset.zero & size, Radius.circular(radius));
    final path = Path()..addRRect(rrect);
    // draw dashes along the path
    const dash = 7.0, gap = 6.0;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(
            metric.extractPath(d, d + dash), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}
