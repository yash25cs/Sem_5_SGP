package `in`.charusat.studytrail

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import kotlin.random.Random

/**
 * `studytrail/focus_extras`: what a focus block can do to the phone around
 * it, both off unless the student turns them on.
 *
 * - `dndAccess` → whether the app may change Do Not Disturb.
 * - `openDndSettings` opens the system page that grants it.
 * - `setDnd {on}` → turns Do Not Disturb on (priority only) for the block,
 *   or puts back what was there before. Replies false without access.
 * - `playSound {kind}` plays "white", "pink" or "brown" noise until
 *   `stopSound`. Made on the phone, so nothing is downloaded or stored.
 *
 * Do Not Disturb set here is remembered: if the app dies mid-block, the next
 * launch puts the phone's own setting back ([restoreLeftover]).
 */
class FocusExtras(private val context: Context) {
  private var noise: Noise? = null

  fun attach(messenger: BinaryMessenger) {
    restoreLeftover()
    MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
      when (call.method) {
        "dndAccess" -> result.success(hasAccess())
        "openDndSettings" -> {
          if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            context.startActivity(
                Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
          }
          result.success(null)
        }
        "setDnd" -> result.success(setDnd(call.argument<Boolean>("on") == true))
        "playSound" -> {
          play(call.argument<String>("kind") ?: "pink")
          result.success(null)
        }
        "stopSound" -> {
          stop()
          result.success(null)
        }
        else -> result.notImplemented()
      }
    }
  }

  /** The engine is going: no sound outlives it. */
  fun detach() = stop()

  private fun manager() =
      context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

  private fun prefs() = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

  private fun hasAccess(): Boolean =
      Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
          manager().isNotificationPolicyAccessGranted

  private fun setDnd(on: Boolean): Boolean {
    if (!hasAccess()) return false
    val nm = manager()
    val p = prefs()
    if (on) {
      // Remember the student's own setting once, so a repeat call mid-block
      // doesn't record our own "priority" as theirs.
      if (!p.contains(KEY_BEFORE)) {
        p.edit().putInt(KEY_BEFORE, nm.currentInterruptionFilter).apply()
      }
      nm.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_PRIORITY)
    } else {
      val before = p.getInt(KEY_BEFORE, -1)
      // Only undo what this app did: if the student changed it themselves
      // during the block, theirs stands.
      if (before != -1 &&
          nm.currentInterruptionFilter == NotificationManager.INTERRUPTION_FILTER_PRIORITY) {
        nm.setInterruptionFilter(before)
      }
      p.edit().remove(KEY_BEFORE).apply()
    }
    return true
  }

  /** A block the app never got to end: put the phone's setting back. */
  private fun restoreLeftover() {
    if (prefs().contains(KEY_BEFORE)) setDnd(false)
  }

  private fun play(kind: String) {
    stop()
    noise = Noise(kind).also { it.start() }
  }

  private fun stop() {
    noise?.halt()
    noise = null
  }

  /** Streams generated noise, fading in so it doesn't start with a burst. */
  private class Noise(private val kind: String) : Thread("focus-noise") {
    @Volatile private var running = true

    fun halt() {
      running = false
    }

    override fun run() {
      val rate = 22_050
      val min = AudioTrack.getMinBufferSize(
          rate, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT)
      val track = AudioTrack.Builder()
          .setAudioAttributes(
              AudioAttributes.Builder()
                  .setUsage(AudioAttributes.USAGE_MEDIA)
                  .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                  .build())
          .setAudioFormat(
              AudioFormat.Builder()
                  .setSampleRate(rate)
                  .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                  .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                  .build())
          .setBufferSizeInBytes(maxOf(min, rate))
          .setTransferMode(AudioTrack.MODE_STREAM)
          .build()
      val buf = ShortArray(2048)
      val rnd = Random(System.nanoTime())
      // Pink (Paul Kellet's filter) and brown (leaky integrator) state.
      var b0 = 0.0; var b1 = 0.0; var b2 = 0.0; var b3 = 0.0; var b4 = 0.0
      var b5 = 0.0; var b6 = 0.0
      var brown = 0.0
      var gain = 0.0
      try {
        track.play()
        while (running) {
          for (i in buf.indices) {
            val white = rnd.nextDouble() * 2 - 1
            val v = when (kind) {
              "white" -> white * 0.35
              "brown" -> {
                brown = (brown + 0.02 * white) / 1.02
                brown * 3.0
              }
              else -> {
                b0 = 0.99886 * b0 + white * 0.0555179
                b1 = 0.99332 * b1 + white * 0.0750759
                b2 = 0.96900 * b2 + white * 0.1538520
                b3 = 0.86650 * b3 + white * 0.3104856
                b4 = 0.55000 * b4 + white * 0.5329522
                b5 = -0.7616 * b5 - white * 0.0168980
                val pink = b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362
                b6 = white * 0.115926
                pink * 0.09
              }
            }
            if (gain < 1.0) gain = minOf(1.0, gain + 1.0 / (rate * 2))
            buf[i] = (v.coerceIn(-1.0, 1.0) * gain * Short.MAX_VALUE * 0.6).toInt().toShort()
          }
          track.write(buf, 0, buf.size)
        }
      } catch (_: Exception) {
        // A sound is a nicety; failing quietly beats crashing the block.
      } finally {
        try {
          track.stop()
        } catch (_: Exception) {
        }
        track.release()
      }
    }
  }

  companion object {
    const val CHANNEL = "studytrail/focus_extras"
    private const val PREFS = "studytrail_focus_extras"
    private const val KEY_BEFORE = "dnd_before"
  }
}
