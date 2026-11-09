import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../data/repositories.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/data_states.dart';
import '../widgets/nav.dart';
import '../widgets/working.dart';

/// A one-page revision sheet for one unit of a material, from the
/// `revision-sheet` Edge Function: read it here, save it as a PDF to print,
/// or copy it.
class RevisionSheetScreen extends StatefulWidget {
  const RevisionSheetScreen({
    super.key,
    required this.materialId,
    this.unitLabel,
    this.materials = const MaterialRepository(),
  });

  final String materialId;

  /// The unit to cover; null for the whole file.
  final String? unitLabel;
  final MaterialRepository materials;

  static Future<void> open(BuildContext context,
          {required String materialId, String? unitLabel}) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            RevisionSheetScreen(materialId: materialId, unitLabel: unitLabel),
      ));

  @override
  State<RevisionSheetScreen> createState() => _RevisionSheetScreenState();
}

class _RevisionSheetScreenState extends State<RevisionSheetScreen> {
  RevisionSheet? _sheet;
  String? _error;
  bool _saving = false;

  static const _messages = [
    'Reading your notes on this unit…',
    'Picking out what the exam asks…',
    'Fitting it on one page…',
    'Almost ready…',
  ];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _sheet = null;
      _error = null;
    });
    try {
      final sheet = await widget.materials
          .requestRevisionSheet(widget.materialId, unitLabel: widget.unitLabel);
      if (mounted) setState(() => _sheet = sheet);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  void _toast(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  Future<void> _copy() async {
    final sheet = _sheet;
    if (sheet == null) return;
    await Clipboard.setData(ClipboardData(text: sheet.asText));
    if (mounted) _toast('Revision sheet copied.');
  }

  /// Saves the sheet as a PDF and hands it to the share sheet, where it can
  /// be printed, saved to Files or sent on.
  Future<void> _savePdf() async {
    final sheet = _sheet;
    if (sheet == null || _saving) return;
    // The PDF's built-in font covers Latin script only; a Hindi or Gujarati
    // sheet would print as boxes, so it's shared as text instead.
    if (!revisionSheetPrintable(sheet)) {
      await SharePlus.instance
          .share(ShareParams(text: sheet.asText, subject: _fileTitle(sheet)));
      return;
    }
    setState(() => _saving = true);
    try {
      final bytes = await revisionSheetPdf(sheet);
      final name =
          '${_fileTitle(sheet).replaceAll(RegExp(r'[^\w\- ]'), '')}.pdf';
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(bytes, mimeType: 'application/pdf', name: name)],
        fileNameOverrides: [name],
        subject: _fileTitle(sheet),
      ));
    } catch (e) {
      if (mounted) _toast('Could not make the PDF. Try Copy instead.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static String _fileTitle(RevisionSheet sheet) =>
      'Revision sheet - ${sheet.unit ?? sheet.title}';

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final sheet = _sheet;
    return Scaffold(
      backgroundColor: p.bg,
      body: Column(
        children: [
          const TopInset(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 20, 6),
            child: Row(
              children: [
                RoundIconButton(Symbols.arrow_back,
                    onTap: () => Navigator.of(context).pop()),
                const SizedBox(width: 8),
                Text('Revision sheet',
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 20,
                        fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          Expanded(
            child: _error != null
                ? Padding(
                    padding: const EdgeInsets.all(20),
                    child: ErrorNotice(message: _error!, onRetry: _fetch),
                  )
                : sheet == null
                    ? const Padding(
                        padding: EdgeInsets.all(20),
                        child: AppCard(
                          padding: EdgeInsets.fromLTRB(16, 20, 16, 18),
                          child: AiWorking(
                              icon: Symbols.article, messages: _messages),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
                        children: [
                          Text(sheet.unit ?? sheet.title,
                              style: TextStyle(
                                  color: p.ink,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.4)),
                          if (sheet.unit != null) ...[
                            const SizedBox(height: 2),
                            Text(sheet.title,
                                style: TextStyle(color: p.ink3, fontSize: 13)),
                          ],
                          if (sheet.pastQuestions > 0) ...[
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: SoftChip(
                                  'Shaped by ${sheet.pastQuestions} past '
                                  'question${sheet.pastQuestions == 1 ? '' : 's'}',
                                  icon: Symbols.history_edu,
                                  tone: ChipTone.amber,
                                  small: true),
                            ),
                          ],
                          const SizedBox(height: 16),
                          for (final (heading, items) in sheet.sections) ...[
                            AppCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(heading,
                                      style: TextStyle(
                                          color: p.primary,
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 8),
                                  for (final item in items)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text('•  ',
                                              style: TextStyle(
                                                  color: p.ink3,
                                                  fontSize: 13.5)),
                                          Expanded(
                                            child: Text(item,
                                                style: TextStyle(
                                                    color: p.ink,
                                                    fontSize: 13.5,
                                                    height: 1.4)),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: PillButton('Save as PDF',
                                    icon: Symbols.picture_as_pdf,
                                    loading: _saving,
                                    onTap: _savePdf),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: PillButton('Copy',
                                    icon: Symbols.content_copy,
                                    variant: PillVariant.outline,
                                    onTap: _copy),
                              ),
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

/// Whether the PDF's built-in Latin font can print [sheet].
bool revisionSheetPrintable(RevisionSheet sheet) =>
    !RegExp(r'[^\u0000-ÿ•–—‘’“”…€]').hasMatch(sheet.asText);

/// [sheet] laid out on A4: title, then each section and its bullets.
Future<Uint8List> revisionSheetPdf(RevisionSheet sheet) {
  final doc = pw.Document(title: sheet.unit ?? sheet.title);
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(40, 36, 40, 36),
    build: (_) => [
      pw.Text(sheet.unit ?? sheet.title,
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
      if (sheet.unit != null)
        pw.Text(sheet.title,
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
      pw.SizedBox(height: 10),
      for (final (heading, items) in sheet.sections) ...[
        pw.SizedBox(height: 8),
        pw.Text(heading,
            style: pw.TextStyle(
                fontSize: 12.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.indigo800)),
        pw.SizedBox(height: 4),
        for (final item in items)
          pw.Bullet(
              text: item,
              style: const pw.TextStyle(fontSize: 10.5, lineSpacing: 1.5)),
      ],
      pw.SizedBox(height: 14),
      pw.Text('Made with StudyTrail',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
    ],
  ));
  return doc.save();
}

/// Picks a material (and a unit of it) to make a revision sheet from. Files
/// for [subjectId] or [goalId] first; only files that have been read. With
/// [material] it starts at that file's units.
Future<void> showRevisionSheetPicker(
  BuildContext context, {
  String? goalId,
  String? subjectId,
  StudyMaterial? material,
  MaterialRepository materials = const MaterialRepository(),
}) async {
  final p = context.p;
  final navigator = Navigator.of(context);
  final picked = await showModalBottomSheet<(String, String?)>(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (_) => _SheetPicker(
        goalId: goalId,
        subjectId: subjectId,
        material: material,
        materials: materials),
  );
  if (picked == null) return;
  await navigator.push(MaterialPageRoute(
    builder: (_) =>
        RevisionSheetScreen(materialId: picked.$1, unitLabel: picked.$2),
  ));
}

/// Two steps in one sheet: a file, then one of its units (or all of it).
/// Pops `(materialId, unitLabel)`.
class _SheetPicker extends StatefulWidget {
  const _SheetPicker({
    this.goalId,
    this.subjectId,
    this.material,
    required this.materials,
  });

  final String? goalId;
  final String? subjectId;
  final StudyMaterial? material;
  final MaterialRepository materials;

  @override
  State<_SheetPicker> createState() => _SheetPickerState();
}

class _SheetPickerState extends State<_SheetPicker> {
  List<StudyMaterial>? _files;
  StudyMaterial? _file;
  List<String>? _units;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.material case final m?) {
      _files = [m];
      _file = m;
      _loadUnits(m);
    } else {
      _loadFiles();
    }
  }

  Future<void> _loadFiles() async {
    try {
      final all = (await widget.materials.getMaterials())
          .where((m) => m.isReady)
          .toList();
      int rank(StudyMaterial m) =>
          m.subjectId != null && m.subjectId == widget.subjectId
              ? 0
              : m.goalId != null && m.goalId == widget.goalId
                  ? 1
                  : 2;
      all.sort((a, b) => rank(a).compareTo(rank(b)));
      if (mounted) setState(() => _files = all);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  void _pickFile(StudyMaterial file) {
    setState(() {
      _file = file;
      _units = null;
    });
    _loadUnits(file);
  }

  Future<void> _loadUnits(StudyMaterial file) async {
    try {
      final units = await widget.materials.getUnits(file.id);
      if (!mounted) return;
      // Nothing to choose between: straight to the whole file.
      if (units.isEmpty) {
        Navigator.of(context).pop((file.id, null));
        return;
      }
      setState(() => _units = units);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final file = _file;
    final title = file == null ? 'Revision sheet' : file.displayName;
    final subtitle = file == null
        ? 'Pick the notes to make it from.'
        : 'Pick a unit, or the whole file.';

    final Widget body;
    if (_error != null) {
      body = Padding(
          padding: const EdgeInsets.all(20),
          child: Text(_error!, style: TextStyle(color: p.error)));
    } else if (_files == null || (file != null && _units == null)) {
      body = const Padding(
          padding: EdgeInsets.all(28),
          child: Center(child: CircularProgressIndicator()));
    } else if (file == null && _files!.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Text(
            'Upload your notes or syllabus first. A revision sheet is made '
            'from what you have uploaded.',
            style: TextStyle(color: p.ink2, fontSize: 13.5, height: 1.4)),
      );
    } else if (file == null) {
      body = Column(children: [
        for (final m in _files!)
          ListTile(
            leading: Icon(Symbols.description, color: p.primary),
            title: Text(m.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.ink, fontWeight: FontWeight.w600)),
            trailing: Icon(Symbols.chevron_right, color: p.ink3),
            onTap: () => _pickFile(m),
          ),
      ]);
    } else {
      body = Column(children: [
        ListTile(
          leading: Icon(Symbols.select_all, color: p.coral),
          title: Text('Whole file',
              style: TextStyle(color: p.ink, fontWeight: FontWeight.w600)),
          onTap: () => Navigator.of(context).pop((file.id, null)),
        ),
        for (final u in _units!)
          ListTile(
            leading: Icon(Symbols.article, color: p.primary),
            title: Text(u,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.ink, fontWeight: FontWeight.w600)),
            onTap: () => Navigator.of(context).pop((file.id, u)),
          ),
      ]);
    }

    return SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 2),
                child: Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(subtitle,
                    style: TextStyle(color: p.ink3, fontSize: 12.5)),
              ),
              body,
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
