import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

/// A screen a widget tap asks for — the path of `studytrail://widget/<path>`
/// in `WidgetLinks` (`WidgetData.kt`).
enum WidgetTarget {
  home,
  focus,
  flashcards,
  chat,
  roadmap,
  achievements;

  /// Null for a link that isn't a widget's, or one this build doesn't know.
  static WidgetTarget? fromUri(Uri? uri) {
    if (uri == null || uri.scheme != 'studytrail' || uri.host != 'widget') {
      return null;
    }
    final path = uri.pathSegments.firstOrNull;
    return WidgetTarget.values.where((t) => t.name == path).firstOrNull;
  }
}

/// One of the home-screen widgets, as the launcher knows it.
enum HomeWidgetKind {
  today('in.charusat.studytrail.StudyTrailWidget'),
  countdown('in.charusat.studytrail.ExamCountdownWidget'),
  streak('in.charusat.studytrail.StreakWidget');

  const HomeWidgetKind(this.provider);

  /// The `AppWidgetProvider` class in the Android app.
  final String provider;
}

/// Feeds the Android home-screen widgets (`StudyTrailWidget.kt`,
/// `ExamCountdownWidget.kt`, `StreakWidget.kt`), and reads their taps.
///
/// It saves facts, not sentences — exam dates rather than "12 days", the day
/// the student last studied rather than "streak safe" — so the widgets'
/// own midnight redraw keeps them right when the app isn't opened. Android
/// only; a no-op elsewhere and in tests. Never throws: the widgets are a
/// nicety, never a reason to fail a screen.
class HomeWidgetSync {
  const HomeWidgetSync._();

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  /// The widgets exist on this platform (Android). Settings lists them only
  /// here.
  static bool get available => _supported;

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Every subject paper as `yyyy-MM-dd<TAB>name` lines, which is what
  /// `WidgetData.kt` reads. A tab or newline in a name would split it.
  @visibleForTesting
  static String? examLines(Iterable<(String, DateTime?)> exams) {
    final lines = [
      for (final (name, date) in exams)
        if (date != null && name.trim().isNotEmpty)
          '${_day(date)}\t${name.replaceAll(RegExp(r'[\t\n\r]'), ' ').trim()}',
    ];
    return lines.isEmpty ? null : lines.join('\n');
  }

  /// The next few local midnights, a minute past — when the countdowns roll
  /// over. A week ahead, so a phone left alone for days still counts down.
  @visibleForTesting
  static List<DateTime> midnights(DateTime now, {int days = 7}) => [
        for (var i = 1; i <= days; i++)
          DateTime(now.year, now.month, now.day + i, 0, 1),
      ];

  static Future<void> push({
    String? goalName,
    DateTime? goalDate,
    Iterable<(String, DateTime?)> subjectExams = const [],
    int streak = 0,
    int bestStreak = 0,
    DateTime? lastStudied,
    int tasksDone = 0,
    int tasksTotal = 0,
    List<String> nextTasks = const [],
  }) async {
    if (!_supported) return;
    try {
      await Future.wait([
        HomeWidget.saveWidgetData<bool>('signed_in', true),
        HomeWidget.saveWidgetData<String>('exams', examLines(subjectExams)),
        HomeWidget.saveWidgetData<String>('exam_name', goalName),
        HomeWidget.saveWidgetData<String>(
            'exam_date', goalDate == null ? null : _day(goalDate)),
        HomeWidget.saveWidgetData<int>('streak', streak),
        HomeWidget.saveWidgetData<int>('streak_best', bestStreak),
        HomeWidget.saveWidgetData<String>(
            'streak_last', lastStudied == null ? null : _day(lastStudied)),
        HomeWidget.saveWidgetData<String>('tasks_date', _day(DateTime.now())),
        HomeWidget.saveWidgetData<int>('tasks_done', tasksDone),
        HomeWidget.saveWidgetData<int>('tasks_total', tasksTotal),
        HomeWidget.saveWidgetData<String>(
            'next_tasks',
            nextTasks.isEmpty
                ? null
                : nextTasks
                    .take(3)
                    .map((t) => t.replaceAll(RegExp(r'[\n\r]'), ' '))
                    .join('\n')),
        // From before the flipper; nothing reads it any more.
        HomeWidget.saveWidgetData<String>('next_task', null),
      ]);
      await _redrawAll();
      final times = midnights(DateTime.now());
      for (final kind in HomeWidgetKind.values) {
        await HomeWidget.scheduleWidgetUpdates(times,
            qualifiedAndroidName: kind.provider);
      }
    } catch (e) {
      debugPrint('Home widget update failed: $e');
    }
  }

  /// On sign-out: the next person to pick up the phone shouldn't see the last
  /// student's exam on the home screen.
  static Future<void> clear() async {
    if (!_supported) return;
    try {
      await Future.wait([
        HomeWidget.saveWidgetData<bool>('signed_in', false),
        for (final key in const [
          'exams',
          'exam_name',
          'exam_date',
          'streak_last',
          'tasks_date',
          'next_tasks',
          'next_task',
        ])
          HomeWidget.saveWidgetData<String>(key, null),
        HomeWidget.saveWidgetData<int>('streak', 0),
        HomeWidget.saveWidgetData<int>('streak_best', 0),
      ]);
      await _redrawAll();
      for (final kind in HomeWidgetKind.values) {
        await HomeWidget.cancelScheduledWidgetUpdates(
            qualifiedAndroidName: kind.provider);
      }
    } catch (e) {
      debugPrint('Home widget clear failed: $e');
    }
  }

  static Future<void> _redrawAll() async {
    for (final kind in HomeWidgetKind.values) {
      await HomeWidget.updateWidget(qualifiedAndroidName: kind.provider);
    }
  }

  /// Taps on a widget while the app is already running.
  static Stream<WidgetTarget> get taps => _supported
      ? HomeWidget.widgetClicked
          .map(WidgetTarget.fromUri)
          .where((t) => t != null)
          .cast<WidgetTarget>()
      : const Stream.empty();

  static bool _launchTaken = false;

  /// The widget tap that launched the app, once per process: the shell is
  /// built again after a sign-out and sign-in, and mustn't reopen it.
  static Future<WidgetTarget?> takeLaunchTarget() async {
    if (!_supported || _launchTaken) return null;
    _launchTaken = true;
    try {
      return WidgetTarget.fromUri(
          await HomeWidget.initiallyLaunchedFromHomeWidget());
    } catch (e) {
      debugPrint('Home widget launch check failed: $e');
      return null;
    }
  }

  /// Whether this launcher can add a widget for the app ("pin" it). False on
  /// iOS, web, and launchers without the feature.
  static Future<bool> canAdd() async {
    if (!_supported) return false;
    try {
      return await HomeWidget.isRequestPinWidgetSupported() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Asks the launcher to add [kind]; it shows its own confirmation.
  static Future<void> add(HomeWidgetKind kind) async {
    if (!_supported) return;
    try {
      await HomeWidget.requestPinWidget(qualifiedAndroidName: kind.provider);
    } catch (e) {
      debugPrint('Home widget pin failed: $e');
    }
  }
}
