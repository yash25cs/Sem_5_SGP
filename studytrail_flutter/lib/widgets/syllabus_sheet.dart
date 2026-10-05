import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/stores.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// A subject's syllabus: add one as a PDF or as typed or pasted text, replace
/// it, or remove it (`0027`). It's read into units straight away, and the
/// roadmap plans that subject from those units the next time it's written.
Future<void> showSyllabusSheet(BuildContext context, Subject subject) {
  final p = context.p;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (_) => _SyllabusSheet(subject: subject),
  );
}

class _SyllabusSheet extends StatelessWidget {
  const _SyllabusSheet({required this.subject});
  final Subject subject;

  Future<void> _pickPdf(BuildContext context) async {
    final home = context.read<HomeStore>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    final file = result?.files.firstOrNull;
    if (file?.path == null) return;
    navigator.pop();
    final ok = await home.addSyllabusFile(subject, File(file!.path!), file.name);
    _report(messenger, home, ok);
  }

  Future<void> _typeIt(BuildContext context) async {
    final home = context.read<HomeStore>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final p = context.p;
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) => _SyllabusTextSheet(subjectName: subject.name),
    );
    if (text == null) return;
    navigator.pop();
    final ok = await home.addSyllabusText(subject, text);
    _report(messenger, home, ok);
  }

  Future<void> _remove(BuildContext context) async {
    final home = context.read<HomeStore>();
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    final ok = await home.removeSyllabus(subject);
    messenger.showSnackBar(SnackBar(
        content: Text(ok
            ? '${subject.name} syllabus removed.'
            : home.error ?? 'Could not remove it.')));
  }

  void _report(ScaffoldMessengerState messenger, HomeStore home, bool ok) {
    messenger.showSnackBar(SnackBar(
      content: Text(ok
          ? '${subject.name} syllabus added. Replace your roadmap from the '
              'Roadmap tab to plan from its units.'
          : home.error ?? "Couldn't add that syllabus. Try again."),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final current = context.watch<HomeStore>().syllabusOf(subject);

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${subject.name} syllabus',
                style: TextStyle(
                    color: p.ink, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
                'Add the syllabus and your roadmap plans ${subject.name} '
                'unit by unit, from what the exam actually covers.',
                style: TextStyle(color: p.ink2, fontSize: 13.5, height: 1.4)),
            const SizedBox(height: 16),
            if (current != null) ...[
              AppCard(
                color: p.card2,
                shadow: false,
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(
                        current.isReady
                            ? Symbols.check_circle
                            : Symbols.error,
                        color: current.isReady ? p.green : p.error,
                        fill: 1,
                        size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(current.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: p.ink,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700)),
                          Text(
                              current.isReady
                                  ? 'Read and ready'
                                  : "Couldn't be read — add it again",
                              style:
                                  TextStyle(color: p.ink3, fontSize: 12)),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => _remove(context),
                      child: Text('Remove',
                          style: TextStyle(
                              color: p.error, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text('Replace it with',
                  style: TextStyle(
                      color: p.ink3,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
            ],
            _Option(
              icon: Symbols.picture_as_pdf,
              title: 'Upload a PDF',
              subtitle: 'The syllabus your college gave you',
              onTap: () => _pickPdf(context),
            ),
            const SizedBox(height: 10),
            _Option(
              icon: Symbols.edit_note,
              title: 'Type or paste it',
              subtitle: 'Units and topics, one unit per line or paragraph',
              onTap: () => _typeIt(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Material(
      color: p.primarySoft,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              IconTile(icon, bg: p.card, fg: p.primary, size: 42, radius: 12),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: p.onPrimarySoft,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(
                            color: p.onPrimarySoft.withValues(alpha: 0.8),
                            fontSize: 12)),
                  ],
                ),
              ),
              Icon(Symbols.chevron_right, color: p.onPrimarySoft),
            ],
          ),
        ),
      ),
    );
  }
}

/// The typed syllabus. Pops the text, or nothing when closed.
///
/// A widget, so the text controller lives exactly as long as the field that
/// uses it (see `_AddSubjectSheet` in set_target_screen.dart for why).
class _SyllabusTextSheet extends StatefulWidget {
  const _SyllabusTextSheet({required this.subjectName});
  final String subjectName;

  @override
  State<_SyllabusTextSheet> createState() => _SyllabusTextSheetState();
}

class _SyllabusTextSheetState extends State<_SyllabusTextSheet> {
  /// Shorter than this is a heading, not a syllabus.
  static const _minChars = 30;

  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final length = _controller.text.trim().length;
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: color, width: width),
        );

    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${widget.subjectName} syllabus',
                  style: TextStyle(
                      color: p.ink, fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('Start each unit on a new line with its name.',
                  style: TextStyle(color: p.ink3, fontSize: 12.5)),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                autofocus: true,
                minLines: 8,
                maxLines: 14,
                maxLength: 20000,
                textCapitalization: TextCapitalization.sentences,
                style: TextStyle(color: p.ink, fontSize: 14, height: 1.45),
                decoration: InputDecoration(
                  hintText: 'Unit 1: Topic name\n'
                      'What it covers…\n\n'
                      'Unit 2: Topic name\n'
                      'What it covers…',
                  hintStyle: TextStyle(color: p.ink3, fontSize: 13.5),
                  filled: true,
                  fillColor: p.card2,
                  counterText: '',
                  contentPadding: const EdgeInsets.all(14),
                  border: border(p.line, 1),
                  enabledBorder: border(p.line, 1),
                  focusedBorder: border(p.primary, 1.6),
                ),
              ),
              const SizedBox(height: 14),
              PillButton('Save syllabus',
                  icon: Symbols.check,
                  onTap: length < _minChars
                      ? null
                      : () => Navigator.of(context).pop(_controller.text)),
            ],
          ),
        ),
      ),
    );
  }
}
