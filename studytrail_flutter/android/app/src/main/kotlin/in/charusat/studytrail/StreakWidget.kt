package `in`.charusat.studytrail

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * The streak (2×1): the flame and the count, and — when tall enough —
 * whether today is done. While today is still to do, a light circles the
 * flame and a tap starts a focus session; once it's done the light stops and
 * a tap opens Achievements.
 */
class StreakWidget : HomeWidgetProvider() {

  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  ) {
    val data = WidgetData(widgetData)
    for (id in appWidgetIds) {
      val views = sizedViews(appWidgetManager, id, listOf(
          0f to { build(context, data, status = false) },
          STATUS_FROM to { build(context, data, status = true) },
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

  private fun build(context: Context, d: WidgetData, status: Boolean): RemoteViews =
      RemoteViews(context.packageName, R.layout.studytrail_streak).apply {
        val done = d.signedIn && d.studiedToday
        setTextViewText(R.id.streak_count, if (d.signedIn) d.streak.toString() else "—")
        setTextViewText(R.id.streak_unit, if (d.signedIn) "day streak" else "Sign in")
        setTextViewText(R.id.streak_status, when {
          done && d.bestStreak > d.streak -> "Done today · best ${d.bestStreak}"
          done -> "Done today"
          d.streak > 0 -> "Study today to keep it"
          else -> "Start one today"
        })
        setViewVisibility(R.id.streak_status_icon, if (done) View.VISIBLE else View.GONE)
        setViewVisibility(
            R.id.streak_status_row,
            if (status && d.signedIn) View.VISIBLE else View.GONE,
        )
        // The circling light: only while there's still something to do today.
        setViewVisibility(R.id.streak_glow, if (d.signedIn && !done) View.VISIBLE else View.GONE)
        setOnClickPendingIntent(
            android.R.id.background,
            WidgetLinks.open(context, if (done) "achievements" else "focus"),
        )
      }

  private companion object {
    /** Height (dp) the status line needs to fit. */
    const val STATUS_FROM = 76f
  }
}
