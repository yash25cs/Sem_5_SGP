package `in`.charusat.studytrail

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Bundle
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * `studytrail/focus_notice`: the ongoing notification for a focus block,
 * posted here rather than through flutter_local_notifications so it can be a
 * live timer.
 *
 * - `show {title, body, endsAt?, total, left}` posts or updates it. With
 *   `endsAt` (epoch ms) the system counts it down by itself; without it the
 *   block is paused. `total` and `left` (seconds) draw the progress bar.
 * - `cancel` takes it down.
 *
 * Its Pause / Resume button comes back to Dart as `action` "pause" or
 * "resume", and a tap on the notification as `tap`.
 *
 * On Android 16 it asks to be promoted to a Live Update: a chip in the status
 * bar that counts down, and on the lock screen and always-on display — the
 * Android counterpart of the iPhone's Dynamic Island. Samsung's Now Bar
 * (One UI 8) and other skins that show Live Updates pick it up too. The
 * student can turn that off per app; older versions show the notification
 * alone.
 */
class FocusNotice(private val context: Context) {

  fun attach(messenger: BinaryMessenger) {
    val ch = MethodChannel(messenger, CHANNEL)
    channel = ch
    ch.setMethodCallHandler { call, result ->
      when (call.method) {
        "show" -> {
          show(
              title = call.argument<String>("title") ?: "Focus session",
              body = call.argument<String>("body") ?: "",
              endsAt = call.argument<Number>("endsAt")?.toLong(),
              total = call.argument<Number>("total")?.toInt() ?: 0,
              left = call.argument<Number>("left")?.toInt() ?: 0,
          )
          result.success(null)
        }
        "cancel" -> {
          manager(context).cancel(ID)
          result.success(null)
        }
        else -> result.notImplemented()
      }
    }
  }

  fun detach() {
    channel?.setMethodCallHandler(null)
    channel = null
  }

  /** The notification was tapped while the app was still running. */
  fun onTap() {
    channel?.invokeMethod("tap", null)
  }

  private fun show(title: String, body: String, endsAt: Long?, total: Int, left: Int) {
    val nm = manager(context)
    ensureChannel(nm)
    val running = endsAt != null

    val b = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      Notification.Builder(context, CHANNEL_ID)
    } else {
      @Suppress("DEPRECATION")
      Notification.Builder(context).setPriority(Notification.PRIORITY_DEFAULT)
    }
    b.setSmallIcon(R.drawable.ic_widget_timer)
        .setContentTitle(title)
        .setContentText(body)
        .setOngoing(true)
        .setAutoCancel(false)
        .setOnlyAlertOnce(true)
        .setVisibility(Notification.VISIBILITY_PUBLIC)
        .setCategory(
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) Notification.CATEGORY_STOPWATCH
            else Notification.CATEGORY_PROGRESS)
        .setContentIntent(openApp())

    if (running) {
      // The system ticks this down, in the notification and in the status
      // bar chip, without the app reposting every second.
      b.setWhen(endsAt!!).setShowWhen(true).setUsesChronometer(true)
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) b.setChronometerCountDown(true)
    } else {
      b.setShowWhen(false)
    }

    val length = total.coerceAtLeast(1)
    val done = (total - left).coerceIn(0, length)
    if (Build.VERSION.SDK_INT >= 36) {
      b.setStyle(
          Notification.ProgressStyle()
              .setProgressSegments(listOf(Notification.ProgressStyle.Segment(length)))
              .setProgress(done))
      // A running chip shows the countdown itself; a paused one says so.
      if (!running) b.setShortCriticalText("Paused")
    } else {
      b.setProgress(length, done, false)
    }

    b.addAction(
        Notification.Action.Builder(
                Icon.createWithResource(context, R.drawable.ic_widget_timer),
                if (running) "Pause" else "Resume",
                button(if (running) ACTION_PAUSE else ACTION_RESUME))
            .build())

    // Notification.EXTRA_REQUEST_PROMOTED_ONGOING (Android 16): ask for the
    // Live Update chip. Ignored by older versions.
    b.addExtras(Bundle().apply { putBoolean("android.requestPromotedOngoing", true) })

    nm.notify(ID, b.build())
  }

  private fun ensureChannel(nm: NotificationManager) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    if (nm.getNotificationChannel(CHANNEL_ID) != null) return
    // Default importance: Live Updates aren't offered for a minimised
    // channel. Silent all the same — it changes every half minute.
    nm.createNotificationChannel(
        NotificationChannel(CHANNEL_ID, "Focus timer", NotificationManager.IMPORTANCE_DEFAULT).apply {
          description = "The countdown while a focus block runs"
          setSound(null, null)
          enableVibration(false)
          setShowBadge(false)
        })
    // The low-importance channel the plugin used before; nothing posts to it.
    nm.deleteNotificationChannel("focus_session")
  }

  private fun openApp(): PendingIntent =
      PendingIntent.getActivity(
          context,
          REQUEST_OPEN,
          Intent(context, MainActivity::class.java)
              .setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
              .putExtra(EXTRA_TAP, true),
          PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

  private fun button(action: String): PendingIntent =
      PendingIntent.getBroadcast(
          context,
          if (action == ACTION_PAUSE) REQUEST_PAUSE else REQUEST_RESUME,
          Intent(context, FocusNoticeReceiver::class.java).setAction(action),
          PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

  companion object {
    const val CHANNEL = "studytrail/focus_notice"
    const val CHANNEL_ID = "focus_live"

    /** NotificationService._focusSessionId: its init clears a stale one. */
    const val ID = 400

    const val EXTRA_TAP = "studytrail.focus_tap"
    const val ACTION_PAUSE = "in.charusat.studytrail.FOCUS_PAUSE"
    const val ACTION_RESUME = "in.charusat.studytrail.FOCUS_RESUME"
    private const val REQUEST_OPEN = 4000
    private const val REQUEST_PAUSE = 4001
    private const val REQUEST_RESUME = 4002

    /** Set while the Flutter engine is up, so a button press can reach it. */
    @Volatile
    var channel: MethodChannel? = null

    fun manager(context: Context): NotificationManager =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
  }
}

/** The Pause / Resume button on the focus notification. */
class FocusNoticeReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    val what = when (intent.action) {
      FocusNotice.ACTION_PAUSE -> "pause"
      FocusNotice.ACTION_RESUME -> "resume"
      else -> return
    }
    val ch = FocusNotice.channel
    if (ch == null) {
      // The app, and the timer with it, is gone: the notice is stale.
      FocusNotice.manager(context).cancel(FocusNotice.ID)
      return
    }
    ch.invokeMethod("action", what)
  }
}
