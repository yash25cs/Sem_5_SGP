import 'dart:math';

import '../models/models.dart';

/// Questions about the student's own files: a unit to explain, a file to
/// summarise, likely exam questions, two units to compare, and a weak spot from
/// quizzes. [random] varies the mix between chats. Empty when there are no
/// ready files — the screen then falls back to general starters.
List<ChatStarter> buildChatStarters({
  required List<StarterSource> sources,
  List<WeakTopic> weak = const [],
  Random? random,
  int count = 4,
}) {
  final rnd = random ?? Random();
  final usable = [
    for (final s in sources)
      if (s.title.trim().isNotEmpty)
        StarterSource(
          title: _cleanTitle(s.title),
          units: _cleanUnits(s.units),
        ),
  ]..shuffle(rnd);
  if (usable.isEmpty) return const [];

  final withUnits = usable.where((s) => s.units.isNotEmpty).toList();
  String unitOf(StarterSource s) => s.units[rnd.nextInt(s.units.length)];

  final out = <ChatStarter>[];
  final seen = <String>{};
  void add(ChatStarter s) {
    if (out.length < count && seen.add(s.prompt)) out.add(s);
  }

  // A weak spot first: it's the one most worth asking about.
  final weakUnit = weak
      .map((w) => (w.unitLabel ?? '').trim())
      .where((u) => u.isNotEmpty)
      .map(_cleanUnit)
      .firstOrNull;
  if (weakUnit != null) {
    add(ChatStarter(
      kind: 'weak',
      label: 'Help with ${_short(_topic(weakUnit))}',
      prompt: 'I keep getting $weakUnit wrong in quizzes. Explain it simply '
          'and point out the mistakes students usually make.',
    ));
  }

  if (withUnits.isNotEmpty) {
    final s = withUnits.first;
    final u = unitOf(s);
    add(ChatStarter(
      kind: 'explain',
      label: 'Explain ${_short(_topic(u))}',
      prompt: 'Explain $u from “${s.title}” in simple words, with an example.',
    ));
  }

  add(ChatStarter(
    kind: 'summary',
    label: 'Summarize ${_short(usable.first.title)}',
    prompt: 'Summarize “${usable.first.title}” in key points I can revise from.',
  ));

  if (withUnits.isNotEmpty) {
    final s = withUnits[withUnits.length > 1 ? 1 : 0];
    final u = unitOf(s);
    add(ChatStarter(
      kind: 'exam',
      label: 'Exam questions: ${_short(_topic(u), 18)}',
      prompt: 'What questions could come in my exam on $u from “${s.title}”? '
          'Give short model answers.',
    ));
  }

  final twoUnits = withUnits.where((s) => s.units.length >= 2).firstOrNull;
  if (twoUnits != null) {
    final picked = [...twoUnits.units]..shuffle(rnd);
    add(ChatStarter(
      kind: 'compare',
      label: 'Compare ${_short(_topic(picked[0]), 14)} & '
          '${_short(_topic(picked[1]), 14)}',
      prompt: 'Compare ${picked[0]} and ${picked[1]} from “${twoUnits.title}”: '
          'how are they different, and how do they connect?',
    ));
  }

  // Still short (files without unit headings): summaries of other files.
  for (final s in usable.skip(1)) {
    add(ChatStarter(
      kind: 'summary',
      label: 'Summarize ${_short(s.title)}',
      prompt: 'Summarize “${s.title}” in key points I can revise from.',
    ));
  }
  return out;
}

/// "1700000000_DBMS_unit3.pdf" → "DBMS unit3".
String _cleanTitle(String t) {
  var s = t.trim().replaceFirst(RegExp(r'^\d{10,}_'), '');
  s = s.replaceFirst(RegExp(r'\.(pdf|txt|docx?|pptx?|png|jpe?g)$',
      caseSensitive: false), '');
  return s.replaceAll('_', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Video units are "9:40 · 1. Algorithms"; the time isn't part of the topic.
String _cleanUnit(String u) => u
    .replaceFirst(RegExp(r'^\d{1,2}(:\d{2}){1,2}\s*·\s*'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

List<String> _cleanUnits(List<String> units) {
  final out = <String>[];
  final seen = <String>{};
  for (final raw in units) {
    final u = _cleanUnit(raw);
    if (u.length < 3 || u.length > 80 || u.toLowerCase() == 'source') continue;
    if (seen.add(u.toLowerCase())) out.add(u);
  }
  return out;
}

/// "Unit 3: Normalisation" → "Normalisation", for a short chip label; the
/// full heading stays in the question that's sent.
String _topic(String u) {
  final t = u
      .replaceFirst(
          RegExp(r'^(unit|chapter|module|lecture|part|topic)\s*[\divxlc]+\s*[:.\-–]\s*',
              caseSensitive: false),
          '')
      .replaceFirst(RegExp(r'^\d+(\.\d+)*[.)]?\s+'), '')
      .trim();
  return t.isEmpty ? u : t;
}

/// Cut at a word boundary for a chip label.
String _short(String s, [int max = 24]) {
  if (s.length <= max) return s;
  final cut = s.substring(0, max);
  final space = cut.lastIndexOf(' ');
  return '${(space > max ~/ 2 ? cut.substring(0, space) : cut).trimRight()}…';
}
