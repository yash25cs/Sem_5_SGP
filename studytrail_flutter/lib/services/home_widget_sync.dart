import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

/// Feeds the Android home-screen widget (`StudyTrailWidget.kt`).
///
/// It saves facts, not sentences — the exam's date rather than "12 days" — so
/// the widget's own midnight refresh keeps the count right when the app isn't
/// opened. Android only; a no-op elsewhere and in tests. Never throws: the
/// widget is a nicety, never a reason to fail a screen.
class HomeWidgetSync {
  const HomeWidgetSync._();

  static const _provider = 'in.charusat.studytrail.StudyTrailWidget';

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static Future<void> push({
    String? examName,
    DateTime? examDate,
    int streak = 0,
    int tasksDone = 0,
    int tasksTotal = 0,
    String? nextTask,
  }) async {
    if (!_supported) return;
    try {
      await Future.wait([
        HomeWidget.saveWidgetData<String>('exam_name', examName),
        HomeWidget.saveWidgetData<String>(
            'exam_date', examDate == null ? null : _day(examDate)),
        HomeWidget.saveWidgetData<int>('streak', streak),
        HomeWidget.saveWidgetData<String>('tasks_date', _day(DateTime.now())),
        HomeWidget.saveWidgetData<int>('tasks_done', tasksDone),
        HomeWidget.saveWidgetData<int>('tasks_total', tasksTotal),
        HomeWidget.saveWidgetData<String>('next_task', nextTask),
      ]);
      await HomeWidget.updateWidget(qualifiedAndroidName: _provider);
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
        for (final key in const [
          'exam_name',
          'exam_date',
          'tasks_date',
          'next_task',
        ])
          HomeWidget.saveWidgetData<String>(key, null),
        HomeWidget.saveWidgetData<int>('streak', 0),
      ]);
      await HomeWidget.updateWidget(qualifiedAndroidName: _provider);
    } catch (e) {
      debugPrint('Home widget clear failed: $e');
    }
  }
}
