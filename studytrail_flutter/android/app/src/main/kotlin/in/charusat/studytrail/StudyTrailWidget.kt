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
 * The Today widget (4×2): days to the next exam, a ring for today's tasks, the
 * next few tasks taking turns, and Focus / Cards / Ask AI buttons.
 *
 * Shorter than its full size it drops the buttons, then the task line. Every
 * part is a way into the app: the body opens Home, each button its screen.
 * Data comes from [WidgetData].
 */
class StudyTrailWidget : HomeWidgetProvider() {

  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  ) {
    val data = WidgetData(widgetData)
    for (id in appWidgetIds) {
      val views = sizedViews(appWidgetManager, id, listOf(
          0f to { build(context, data, tasks = false, actions = false) },
          TASKS_FROM to { build(context, data, tasks = true, actions = false) },
          ACTIONS_FROM to { build(context, data, tasks = true, actions = true) },
      ))
      appWidgetManager.updateAppWidget(id, views)
    }
  }

  /** Below Android 12 the size decides the layout, so a resize redraws. */
  override fun onAppWidgetOptionsChanged(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetId: Int,
      newOptions: Bundle,
  ) {
    onUpdate(context, appWidgetManager, intArrayOf(appWidgetId), HomeWidgetPlugin.getData(context))
  }

  private fun build(
      context: Context,
      d: WidgetData,
      tasks: Boolean,
      actions: Boolean,
  ): RemoteViews = RemoteViews(context.packageName, R.layout.studytrail_widget).apply {
    val exam = d.nextExam
    setTextViewText(R.id.widget_days, when {
      !d.signedIn -> "StudyTrail"
      exam == null && d.hadExams -> "Exams done"
      exam == null -> "No exam set"
      exam.days == 0L -> "Exam today"
      exam.days == 1L -> "1 day"
      else -> "${exam.days} days"
    })
    setTextViewText(R.id.widget_exam, when {
      !d.signedIn -> "Sign in to StudyTrail"
      exam == null && d.hadExams -> "Well done — set your next target"
      exam == null -> "Set a target in StudyTrail"
      exam.days == 0L -> "${exam.name} · good luck!"
      exam.days == 1L -> "to ${exam.name} · tomorrow"
      else -> "to ${exam.name} · ${WidgetData.label(exam.date)}"
    })

    setViewVisibility(
        R.id.widget_streak_chip,
        if (d.signedIn && d.streak > 0) View.VISIBLE else View.GONE,
    )
    setTextViewText(R.id.widget_streak, d.streak.toString())

    val counted = d.signedIn && d.tasksForToday && d.tasksTotal > 0
    setProgressBar(
        R.id.widget_ring,
        if (counted) d.tasksTotal else 1,
        if (counted) d.tasksDone.coerceAtMost(d.tasksTotal) else 0,
        false,
    )
    setTextViewText(R.id.widget_ring_text, if (counted) "${d.tasksDone}/${d.tasksTotal}" else "—")

    // One line per upcoming task; the flipper slides between them.
    removeAllViews(R.id.widget_next)
    for (line in taskLines(d)) {
      addView(R.id.widget_next, RemoteViews(context.packageName, R.layout.studytrail_widget_task_line).apply {
        setTextViewText(R.id.widget_task_line, line)
      })
    }
    setViewVisibility(R.id.widget_next, if (tasks) View.VISIBLE else View.GONE)
    setViewVisibility(R.id.widget_actions, if (actions) View.VISIBLE else View.GONE)

    setOnClickPendingIntent(android.R.id.background, WidgetLinks.open(context, "home"))
    setOnClickPendingIntent(R.id.widget_action_focus, WidgetLinks.open(context, "focus"))
    setOnClickPendingIntent(R.id.widget_action_cards, WidgetLinks.open(context, "flashcards"))
    setOnClickPendingIntent(R.id.widget_action_chat, WidgetLinks.open(context, "chat"))
  }

  private fun taskLines(d: WidgetData): List<String> = when {
    !d.signedIn -> listOf("Sign in to see today's plan")
    !d.tasksForToday -> listOf("Open StudyTrail to plan today")
    d.tasksTotal == 0 -> listOf("Nothing planned yet — tap to plan today")
    d.tasksDone >= d.tasksTotal -> listOf("All ${d.tasksTotal} tasks done today 🎉")
    d.nextTasks.isEmpty() -> listOf("${d.tasksDone} of ${d.tasksTotal} done today")
    else -> d.nextTasks.mapIndexed { i, task -> if (i == 0) "Next · $task" else "Then · $task" }
  }

  private companion object {
    /** Heights (dp) the task line, then the buttons, need to fit. */
    const val TASKS_FROM = 135f
    const val ACTIONS_FROM = 178f
  }
}
