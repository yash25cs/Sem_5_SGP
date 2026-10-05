package `in`.charusat.studytrail

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.util.SizeF
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/** One paper still to sit: its name, and whole days from today. */
internal data class Exam(val name: String, val days: Long, val date: Calendar)

/**
 * What the app last saved for the widgets, read as of [now].
 *
 * The app saves facts, not sentences — exam dates, the day the tasks were
 * counted, the day the student last studied — so every widget works out "days
 * left", "today" and "is the streak still alive" when it draws. A widget the
 * app hasn't touched since last week is still right. Keys are written by
 * lib/services/home_widget_sync.dart.
 */
internal class WidgetData(prefs: SharedPreferences, now: Calendar = Calendar.getInstance()) {

  private val today: Calendar = startOfDay(now)

  /**
   * False after sign-out, and before the app has ever saved anything. An
   * install from before this key existed counts as signed in if it saved
   * today's tasks (sign-out removes those).
   */
  val signedIn: Boolean = prefs.getBoolean("signed_in", prefs.contains("tasks_date"))

  /** Papers from today on, soonest first. */
  val exams: List<Exam>

  /** Whether any exam was saved at all, so "none left" can say "all done". */
  val hadExams: Boolean

  val nextExam: Exam? get() = exams.firstOrNull()

  /** The streak as it stands today: 0 once a whole day has been missed. */
  val streak: Int

  val bestStreak: Int = prefs.getInt("streak_best", 0)

  /** Today already counts towards the streak. */
  val studiedToday: Boolean

  /** The task counts are today's, not yesterday's left over. */
  val tasksForToday: Boolean

  val tasksDone: Int = prefs.getInt("tasks_done", 0)
  val tasksTotal: Int = prefs.getInt("tasks_total", 0)

  /** Up to three unticked tasks, in the order Home lists them. */
  val nextTasks: List<String> =
      prefs.getString("next_tasks", null)
          ?.split('\n')
          ?.map { it.trim() }
          ?.filter { it.isNotEmpty() }
          ?.take(3)
          ?: emptyList()

  init {
    // Subject papers ("yyyy-MM-dd<TAB>name" per line), or else the goal's
    // own date when no subject has one.
    val saved = prefs.getString("exams", null)
        ?.split('\n')
        ?.mapNotNull { line ->
          val tab = line.indexOf('\t')
          if (tab <= 0) return@mapNotNull null
          val date = parse(line.substring(0, tab)) ?: return@mapNotNull null
          Exam(line.substring(tab + 1).trim(), daysBetween(today, date), date)
        }
        .orEmpty()
        .ifEmpty {
          val name = prefs.getString("exam_name", null)
          val date = prefs.getString("exam_date", null)?.let { parse(it) }
          if (name == null || date == null) emptyList()
          else listOf(Exam(name, daysBetween(today, date), date))
        }
    hadExams = saved.isNotEmpty()
    exams = saved.filter { it.days >= 0 }.sortedBy { it.days }

    val savedStreak = prefs.getInt("streak", 0)
    val sinceLast = prefs.getString("streak_last", null)
        ?.let { parse(it) }
        ?.let { daysBetween(it, today) }
    studiedToday = sinceLast == 0L
    streak = if (sinceLast != null && sinceLast > 1) 0 else savedStreak

    tasksForToday = prefs.getString("tasks_date", null)
        ?.let { parse(it) }
        ?.let { daysBetween(today, it) == 0L } ?: false
  }

  companion object {
    private val dayFormat = SimpleDateFormat("EEE, d MMM", Locale.ENGLISH)

    /** "Fri, 20 Nov". English, like the rest of the app. */
    fun label(date: Calendar): String = dayFormat.format(date.time)

    private fun parse(date: String): Calendar? = try {
      SimpleDateFormat("yyyy-MM-dd", Locale.US).parse(date)
          ?.let { startOfDay(Calendar.getInstance().apply { time = it }) }
    } catch (_: Exception) {
      null
    }

    private fun startOfDay(c: Calendar): Calendar = (c.clone() as Calendar).apply {
      set(Calendar.HOUR_OF_DAY, 0)
      set(Calendar.MINUTE, 0)
      set(Calendar.SECOND, 0)
      set(Calendar.MILLISECOND, 0)
    }

    /** Whole days from [from] to [to]; rounding absorbs a daylight-saving hour. */
    private fun daysBetween(from: Calendar, to: Calendar): Long =
        Math.round((to.timeInMillis - from.timeInMillis) / 86_400_000.0)
  }
}

/** Where a tap on a widget takes the student. Read by lib/services/home_widget_sync.dart. */
internal object WidgetLinks {
  /** Opens the app at [target]: home, focus, flashcards, chat, roadmap or achievements. */
  fun open(context: Context, target: String): PendingIntent =
      HomeWidgetLaunchIntent.getActivity(
          context,
          MainActivity::class.java,
          Uri.parse("studytrail://widget/$target"),
      )
}

/**
 * A widget's views for its current size.
 *
 * [layouts] maps the smallest height (dp) each variant needs to how to build
 * it, smallest first. Android 12+ is handed all of them and switches by
 * itself as the widget is resized or the phone turns; older versions get the
 * one that fits the portrait height the launcher reports.
 */
internal fun sizedViews(
    manager: AppWidgetManager,
    widgetId: Int,
    layouts: List<Pair<Float, () -> RemoteViews>>,
): RemoteViews {
  if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
    return RemoteViews(layouts.associate { (height, build) -> SizeF(0f, height) to build() })
  }
  val height = manager.getAppWidgetOptions(widgetId)
      .getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0)
  // 0 means the launcher didn't say; the default size fits the fullest one.
  val fits = layouts.lastOrNull { (needs, _) -> height == 0 || height >= needs }
  return (fits ?: layouts.first()).second()
}
