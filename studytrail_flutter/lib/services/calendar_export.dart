import 'dart:convert';

import 'package:share_plus/share_plus.dart';

import '../data/repositories.dart';
import '../models/models.dart';

/// Exam dates, roadmap weeks and upcoming study tasks as an iCalendar (.ics)
/// file, for Google Calendar, Outlook or the phone's own calendar to import.
///
/// Everything is an all-day event. Exams carry reminders a week and a day
/// before. Event ids are stable, so importing again updates rather than
/// duplicates in calendars that honour UIDs.
class CalendarExport {
  const CalendarExport._();

  /// The file's text. Pure, so it can be tested without a network.
  static String build({
    required List<Goal> goals,
    Map<String, List<Subject>> subjectsByGoal = const {},
    Goal? roadmapGoal,
    List<Milestone> milestones = const [],
    List<DailyTask> tasks = const [],
    DateTime? now,
  }) {
    final stamp = _utcStamp(now ?? DateTime.now());
    final out = <String>[
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//StudyTrail//Study plan//EN',
      'CALSCALE:GREGORIAN',
      'METHOD:PUBLISH',
      'X-WR-CALNAME:StudyTrail',
    ];

    void event({
      required String uid,
      required DateTime start,
      DateTime? end,
      required String summary,
      String? description,
      bool remind = false,
    }) {
      final first = DateTime(start.year, start.month, start.day);
      final last = end == null
          ? first.add(const Duration(days: 1))
          : DateTime(end.year, end.month, end.day);
      out.addAll([
        'BEGIN:VEVENT',
        'UID:$uid@studytrail',
        'DTSTAMP:$stamp',
        'DTSTART;VALUE=DATE:${_date(first)}',
        'DTEND;VALUE=DATE:${_date(last)}',
        'SUMMARY:${_text(summary)}',
        if (description != null && description.isNotEmpty)
          'DESCRIPTION:${_text(description)}',
        'TRANSP:TRANSPARENT',
        if (remind)
          for (final before in const ['-P7D', '-P1D']) ...[
            'BEGIN:VALARM',
            'ACTION:DISPLAY',
            'DESCRIPTION:${_text(summary)}',
            'TRIGGER:$before',
            'END:VALARM',
          ],
        'END:VEVENT',
      ]);
    }

    for (final goal in goals) {
      final subjects = subjectsByGoal[goal.id] ?? const <Subject>[];
      final dated = subjects.where((s) => s.examDate != null).toList();
      for (final s in dated) {
        event(
          uid: 'exam-${s.id}',
          start: s.examDate!,
          summary: 'Exam: ${s.name}',
          description: goal.name,
          remind: true,
        );
      }
      // The goal's own date is the last exam; it's only worth its own event
      // when no subject carries a date of its own.
      if (goal.examDate != null && dated.isEmpty) {
        event(
          uid: 'goal-${goal.id}',
          start: goal.examDate!,
          summary: 'Exam: ${goal.name}',
          remind: true,
        );
      }
    }

    final start = roadmapGoal?.roadmapStartedOn;
    if (start != null) {
      final weeks = [...milestones]
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      for (final (i, m) in weeks.indexed) {
        final from = start.add(Duration(days: 7 * i));
        event(
          uid: 'week-${m.id}',
          start: from,
          end: from.add(const Duration(days: 7)),
          summary: '${m.weekLabel ?? 'Week ${i + 1}'}: ${m.title}',
          description: [for (final t in m.tasks) '• ${t.name}'].join('\n'),
        );
      }
    }

    for (final t in tasks) {
      event(
        uid: 'task-${t.id}',
        start: t.scheduledDate,
        summary: 'Study: ${t.title}',
        description: [
          if ((t.subjectName ?? '').isNotEmpty) t.subjectName!,
          if (t.durationMin != null) '${t.durationMin} min',
        ].join(' · '),
      );
    }

    out.add('END:VCALENDAR');
    // RFC 5545: CRLF line endings, lines folded at 75 octets.
    return '${out.expand(_fold).join('\r\n')}\r\n';
  }

  /// Gathers everything from the server and opens the share sheet with the
  /// file. Returns how many events it held.
  static Future<int> collectAndShare() async {
    const goalsRepo = GoalRepository();
    final goals = await goalsRepo.getGoals();
    final subjects = {
      for (final g in goals) g.id: await goalsRepo.getSubjects(g.id),
    };
    final active = goals.where((g) => g.isActive).firstOrNull;
    final milestones = active == null
        ? const <Milestone>[]
        : await const RoadmapRepository().getMilestones(active.id);
    final tasks = await const TaskRepository().getUpcomingTasks();

    final ics = build(
      goals: goals,
      subjectsByGoal: subjects,
      roadmapGoal: active,
      milestones: milestones,
      tasks: tasks,
    );
    final events = 'BEGIN:VEVENT'.allMatches(ics).length;
    if (events == 0) return 0;

    await SharePlus.instance.share(ShareParams(
      files: [
        XFile.fromData(utf8.encode(ics),
            mimeType: 'text/calendar', name: 'studytrail.ics'),
      ],
      fileNameOverrides: const ['studytrail.ics'],
      subject: 'StudyTrail study plan',
    ));
    return events;
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}${_two(d.month)}${_two(d.day)}';

  static String _utcStamp(DateTime t) {
    final u = t.toUtc();
    return '${_date(u)}T${_two(u.hour)}${_two(u.minute)}${_two(u.second)}Z';
  }

  /// TEXT escaping: backslash, semicolon, comma, newline.
  static String _text(String s) => s
      .replaceAll('\\', '\\\\')
      .replaceAll(';', '\\;')
      .replaceAll(',', '\\,')
      .replaceAll('\r\n', '\n')
      .replaceAll('\n', '\\n');

  /// Folds one content line into 75-octet pieces, continuations starting with
  /// a space, never splitting a UTF-8 character.
  static Iterable<String> _fold(String line) sync* {
    if (utf8.encode(line).length <= 75) {
      yield line;
      return;
    }
    final buf = StringBuffer();
    var octets = 0;
    var limit = 75;
    for (final rune in line.runes) {
      final ch = String.fromCharCode(rune);
      final size = utf8.encode(ch).length;
      if (octets + size > limit) {
        yield buf.toString();
        buf
          ..clear()
          ..write(' ');
        octets = 1;
        limit = 75;
      }
      buf.write(ch);
      octets += size;
    }
    if (buf.isNotEmpty) yield buf.toString();
  }
}
