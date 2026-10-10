import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/local_prefs.dart';
import '../data/repositories.dart';
import '../models/models.dart';

/// One all-day entry for the phone's calendar.
@immutable
class CalendarEvent {
  const CalendarEvent({
    required this.key,
    required this.title,
    required this.start,
    required this.end,
    this.description = '',
    this.remindDaysBefore = const [],
  });

  /// StudyTrail's own id for it (`exam-<subject id>`), stable across syncs so
  /// the same event is updated rather than added again.
  final String key;
  final String title;
  final String description;

  /// First day, and the day after the last (exclusive), date-only.
  final DateTime start;
  final DateTime end;

  /// Reminders, in whole days before the event.
  final List<int> remindDaysBefore;

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Map<String, Object> toChannel() => {
        'key': key,
        'title': title,
        'description': description,
        'start': _day(start),
        'end': _day(end),
        'reminders': [for (final d in remindDaysBefore) d * 24 * 60],
      };
}

/// Why a sync didn't happen.
enum CalendarSyncFailure { denied, noCalendar, unsupported, failed }

/// What a sync did: how many events are in the calendar now, and which one.
class CalendarSyncResult {
  const CalendarSyncResult({this.events = 0, this.calendar, this.failure});
  final int events;
  final String? calendar;
  final CalendarSyncFailure? failure;
  bool get ok => failure == null;
}

/// Puts exam dates, roadmap weeks and upcoming study tasks straight into the
/// phone's calendar (Android's calendar provider, through `MainActivity`),
/// and keeps them there: each sync updates what it wrote before and removes
/// what no longer exists — a finished task, a deleted goal.
///
/// Events go in the phone's main calendar, so they show in Google Calendar
/// and sync with it. Exams carry reminders a week and a day before.
class CalendarSync {
  const CalendarSync._();

  static const _channel = MethodChannel('studytrail/calendar');

  /// Everything worth a calendar entry. Pure, so it can be tested.
  static List<CalendarEvent> events({
    required List<Goal> goals,
    Map<String, List<Subject>> subjectsByGoal = const {},
    Goal? roadmapGoal,
    List<Milestone> milestones = const [],
    List<DailyTask> tasks = const [],
  }) {
    DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
    DateTime next(DateTime d) => day(d).add(const Duration(days: 1));
    final out = <CalendarEvent>[];

    for (final goal in goals) {
      final subjects = subjectsByGoal[goal.id] ?? const <Subject>[];
      final dated = subjects.where((s) => s.examDate != null).toList();
      for (final s in dated) {
        out.add(CalendarEvent(
          key: 'exam-${s.id}',
          title: 'Exam: ${s.name}',
          description: goal.name,
          start: day(s.examDate!),
          end: next(s.examDate!),
          remindDaysBefore: const [7, 1],
        ));
      }
      // The goal's own date is the last exam; it's only worth its own event
      // when no subject carries a date of its own.
      if (goal.examDate != null && dated.isEmpty) {
        out.add(CalendarEvent(
          key: 'goal-${goal.id}',
          title: 'Exam: ${goal.name}',
          start: day(goal.examDate!),
          end: next(goal.examDate!),
          remindDaysBefore: const [7, 1],
        ));
      }
    }

    final start = roadmapGoal?.roadmapStartedOn;
    if (start != null) {
      final weeks = [...milestones]
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      for (final (i, m) in weeks.indexed) {
        final from = day(start).add(Duration(days: 7 * i));
        out.add(CalendarEvent(
          key: 'week-${m.id}',
          title: '${m.weekLabel ?? 'Week ${i + 1}'}: ${m.title}',
          description: [for (final t in m.tasks) '• ${t.name}'].join('\n'),
          start: from,
          end: from.add(const Duration(days: 7)),
        ));
      }
    }

    for (final t in tasks) {
      out.add(CalendarEvent(
        key: 'task-${t.id}',
        title: 'Study: ${t.title}',
        description: [
          if ((t.subjectName ?? '').isNotEmpty) t.subjectName!,
          if (t.durationMin != null) '${t.durationMin} min',
        ].join(' · '),
        start: day(t.scheduledDate),
        end: next(t.scheduledDate),
      ));
    }
    return out;
  }

  /// Reads the plan from the server and writes it into the calendar, asking
  /// for calendar access the first time.
  static Future<CalendarSyncResult> syncNow() async {
    if (defaultTargetPlatform != TargetPlatform.android || kIsWeb) {
      return const CalendarSyncResult(failure: CalendarSyncFailure.unsupported);
    }
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

    return write(events(
      goals: goals,
      subjectsByGoal: subjects,
      roadmapGoal: active,
      milestones: milestones,
      tasks: tasks,
    ));
  }

  /// Writes [list] into the calendar, replacing the previous sync's events.
  static Future<CalendarSyncResult> write(List<CalendarEvent> list) async {
    try {
      final known = await LocalPrefs.calendarEvents();
      final res = await _channel.invokeMapMethod<String, Object?>('sync', {
        'events': [for (final e in list) e.toChannel()],
        'known': known,
      });
      final ids = <String, int>{
        for (final e in ((res?['ids'] as Map?) ?? const {}).entries)
          if (e.value is num) e.key as String: (e.value as num).toInt(),
      };
      await LocalPrefs.setCalendarEvents(ids);
      return CalendarSyncResult(
          events: ids.length, calendar: res?['calendar'] as String?);
    } on PlatformException catch (e) {
      return CalendarSyncResult(failure: switch (e.code) {
        'denied' => CalendarSyncFailure.denied,
        'no_calendar' => CalendarSyncFailure.noCalendar,
        _ => CalendarSyncFailure.failed,
      });
    } on MissingPluginException {
      return const CalendarSyncResult(failure: CalendarSyncFailure.unsupported);
    }
  }

  /// Takes every event StudyTrail added back out of the calendar.
  static Future<void> removeAll() async {
    try {
      final known = await LocalPrefs.calendarEvents();
      if (known.isNotEmpty) {
        await _channel.invokeMethod<void>('remove', {'known': known});
      }
      await LocalPrefs.setCalendarEvents({});
    } catch (_) {
      // Already gone, or access was withdrawn: nothing more to do here.
    }
  }

  /// Keeps the calendar current when sync is on: on app open and resume.
  /// Never asks for access and never throws — if access was withdrawn, the
  /// next tap in Settings will say so.
  static Future<void> refreshIfOn() async {
    try {
      if (!await LocalPrefs.calendarSync()) return;
      if (!await _channel.invokeMethod<bool>('hasAccess').then((v) => v ?? false)) {
        return;
      }
      await syncNow();
    } catch (_) {}
  }
}
