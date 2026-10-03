package `in`.charusat.studytrail

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/**
 * The home-screen widget: days to the next exam and today's tasks.
 *
 * The app saves raw facts (the exam's date, today's date with its task counts),
 * not finished sentences, so "days left" and "today" stay right when the
 * widget refreshes on its own at midnight without the app being opened.
 * Keys are written by lib/services/home_widget_sync.dart.
 */
class StudyTrailWidget : HomeWidgetProvider() {

  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  ) {
    val today = startOfDay(Calendar.getInstance())
    val examName = widgetData.getString("exam_name", null)
    val examDays = widgetData.getString("exam_date", null)?.let { parse(it) }
        ?.let { daysBetween(today, it) }
    val streak = widgetData.getInt("streak", 0)
    val tasksForToday = widgetData.getString("tasks_date", null)
        ?.let { parse(it) }
        ?.let { daysBetween(today, it) == 0L } ?: false
    val done = widgetData.getInt("tasks_done", 0)
    val total = widgetData.getInt("tasks_total", 0)
    val next = widgetData.getString("next_task", null)

    val days = when {
      examDays == null -> "No exam set"
      examDays < 0 -> "Exam done"
      examDays == 0L -> "Exam today"
      examDays == 1L -> "1 day"
      else -> "$examDays days"
    }
    val exam = when {
      examName == null -> "Set a target in StudyTrail"
      examDays != null && examDays > 0 -> "to $examName"
      else -> examName
    }
    val tasks = when {
      !tasksForToday -> "Open StudyTrail to plan today"
      total == 0 -> "Nothing planned today"
      done >= total -> "All $total tasks done today"
      next != null -> "$done of $total done · next: $next"
      else -> "$done of $total done today"
    }

    for (id in appWidgetIds) {
      val views = RemoteViews(context.packageName, R.layout.studytrail_widget).apply {
        setTextViewText(R.id.widget_days, days)
        setTextViewText(R.id.widget_exam, exam)
        setTextViewText(R.id.widget_tasks, tasks)
        setTextViewText(R.id.widget_streak, if (streak > 0) "🔥 $streak" else "")
        setOnClickPendingIntent(
            R.id.widget_root,
            HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
        )
      }
      appWidgetManager.updateAppWidget(id, views)
    }
  }

  private fun parse(date: String): Calendar? = try {
    val parsed = SimpleDateFormat("yyyy-MM-dd", Locale.US).parse(date)
    parsed?.let { startOfDay(Calendar.getInstance().apply { time = it }) }
  } catch (_: Exception) {
    null
  }

  private fun startOfDay(c: Calendar): Calendar = c.apply {
    set(Calendar.HOUR_OF_DAY, 0)
    set(Calendar.MINUTE, 0)
    set(Calendar.SECOND, 0)
    set(Calendar.MILLISECOND, 0)
  }

  /** Whole days from [from] to [to]; rounding absorbs a daylight-saving hour. */
  private fun daysBetween(from: Calendar, to: Calendar): Long =
      Math.round((to.timeInMillis - from.timeInMillis) / 86_400_000.0)
}
