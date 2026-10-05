package `in`.charusat.studytrail

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.os.Bundle
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * The exam countdown (2×2): days to the next paper, its subject and date, and
 * how many papers are left. After a paper's day it moves on to the next one by
 * itself — the app saves every subject's date, not just the soonest.
 *
 * Tapping opens the Roadmap, or Home when there is no exam date to count to.
 */
class ExamCountdownWidget : HomeWidgetProvider() {

  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  ) {
    val data = WidgetData(widgetData)
    for (id in appWidgetIds) {
      val views = sizedViews(appWidgetManager, id, listOf(
          0f to { build(context, data, full = false) },
          FULL_FROM to { build(context, data, full = true) },
      ))
      appWidgetManager.updateAppWidget(id, views)
    }
  }

  override fun onAppWidgetOptionsChanged(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetId: Int,
      newOptions: Bundle,
  ) {
    onUpdate(context, appWidgetManager, intArrayOf(appWidgetId), HomeWidgetPlugin.getData(context))
  }

  private fun build(context: Context, d: WidgetData, full: Boolean): RemoteViews =
      RemoteViews(context.packageName, R.layout.studytrail_countdown).apply {
        val exam = d.nextExam
        val left = d.exams.size
        val (big, unit, subject, date) = when {
          !d.signedIn -> Lines("—", "Sign in to StudyTrail", "", "")
          exam == null && d.hadExams -> Lines("Done", "all exams finished", "Well done!", "Set your next target")
          exam == null -> Lines("—", "no exam dates yet", "Tap to add one", "")
          exam.days == 0L -> Lines(
              "Today", "good luck!", exam.name,
              if (left > 1) "then ${left - 1} more" else "last paper",
          )
          else -> Lines(
              exam.days.toString(),
              if (exam.days == 1L) "day to go" else "days to go",
              exam.name,
              WidgetData.label(exam.date) + if (left > 1) " · $left papers left" else "",
          )
        }
        setTextViewText(R.id.countdown_days, big)
        // A number stays big; a word is shrunk to fit the 2×2 width.
        setTextViewTextSize(
            R.id.countdown_days,
            TypedValue.COMPLEX_UNIT_SP,
            if (big.all { it.isDigit() }) 46f else 32f,
        )
        setTextViewText(R.id.countdown_unit, unit)
        setTextViewText(R.id.countdown_subject, subject)
        setTextViewText(R.id.countdown_date, date)
        setViewVisibility(R.id.countdown_subject, if (subject.isEmpty()) View.GONE else View.VISIBLE)
        setViewVisibility(R.id.countdown_header, if (full) View.VISIBLE else View.GONE)
        setViewVisibility(
            R.id.countdown_date,
            if (full && date.isNotEmpty()) View.VISIBLE else View.GONE,
        )
        setOnClickPendingIntent(
            android.R.id.background,
            WidgetLinks.open(context, if (exam == null) "home" else "roadmap"),
        )
      }

  private data class Lines(val big: String, val unit: String, val subject: String, val date: String)

  private companion object {
    /** Height (dp) the header and date line need to fit. */
    const val FULL_FROM = 148f
  }
}
