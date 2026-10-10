package `in`.charusat.studytrail

import android.Manifest
import android.app.Activity
import android.content.ContentUris
import android.content.ContentValues
import android.content.pm.PackageManager
import android.graphics.Color
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.CalendarContract
import android.provider.CalendarContract.Calendars
import android.provider.CalendarContract.Events
import android.provider.CalendarContract.Reminders
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

/**
 * `studytrail/calendar`: writes StudyTrail's exams and plan straight into the
 * phone's calendar provider, so they appear in Google Calendar without
 * importing a file.
 *
 * - `hasAccess` → whether calendar permission is granted.
 * - `sync {events, known}` → asks for permission if needed, then for each
 *   event updates the row `known[key]` points at, or inserts a new one in the
 *   main calendar; rows in `known` with no event any more are deleted.
 *   Replies `{calendar, ids}` with the row id for every key.
 * - `remove {known}` → deletes those rows.
 *
 * Events are all-day, which the provider wants at UTC midnight with a UTC
 * time zone. Work runs off the main thread.
 */
class CalendarChannel(private val activity: Activity) {
    private val main = Handler(Looper.getMainLooper())
    private var pending: Pair<MethodCall, MethodChannel.Result>? = null

    fun attach(messenger: BinaryMessenger) {
        MethodChannel(messenger, "studytrail/calendar").setMethodCallHandler { call, result ->
            when (call.method) {
                "hasAccess" -> result.success(hasAccess())
                "sync", "remove" -> {
                    if (hasAccess()) {
                        run(call, result)
                    } else if (pending != null) {
                        result.error("busy", "Already asking for calendar access", null)
                    } else {
                        pending = call to result
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            activity.requestPermissions(PERMISSIONS, REQUEST_CODE)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    fun onPermissionResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != REQUEST_CODE) return
        val (call, result) = pending ?: return
        pending = null
        if (grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }) {
            run(call, result)
        } else {
            result.error("denied", "Calendar access was not allowed", null)
        }
    }

    private fun hasAccess(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            PERMISSIONS.all { activity.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }

    private fun run(call: MethodCall, result: MethodChannel.Result) {
        Thread {
            try {
                val reply: Any? = when (call.method) {
                    "sync" -> sync(call)
                    else -> {
                        known(call).values.forEach { delete(it) }
                        null
                    }
                }
                main.post { result.success(reply) }
            } catch (e: NoCalendar) {
                main.post { result.error("no_calendar", e.message, null) }
            } catch (e: Exception) {
                main.post { result.error("failed", e.message, null) }
            }
        }.start()
    }

    @Suppress("UNCHECKED_CAST")
    private fun known(call: MethodCall): Map<String, Long> =
        ((call.argument<Map<String, Any>>("known")) ?: emptyMap())
            .mapValues { (it.value as Number).toLong() }

    @Suppress("UNCHECKED_CAST")
    private fun sync(call: MethodCall): Map<String, Any> {
        val events = (call.argument<List<Map<String, Any>>>("events")) ?: emptyList()
        val known = known(call)
        val (calendarId, calendarName) = pickCalendar()
        val ids = HashMap<String, Long>()

        for (e in events) {
            val key = e["key"] as String
            val values = ContentValues().apply {
                put(Events.TITLE, e["title"] as String)
                put(Events.DESCRIPTION, e["description"] as? String ?: "")
                put(Events.DTSTART, day(e["start"] as String))
                put(Events.DTEND, day(e["end"] as String))
                put(Events.ALL_DAY, 1)
                put(Events.EVENT_TIMEZONE, "UTC")
                put(Events.AVAILABILITY, Events.AVAILABILITY_FREE)
            }
            val reminders = (e["reminders"] as? List<Number>)?.map { it.toInt() } ?: emptyList()

            val existing = known[key]?.takeIf { exists(it) }
            val id = if (existing != null) {
                activity.contentResolver.update(
                    ContentUris.withAppendedId(Events.CONTENT_URI, existing), values, null, null)
                existing
            } else {
                values.put(Events.CALENDAR_ID, calendarId)
                val uri = activity.contentResolver.insert(Events.CONTENT_URI, values)
                    ?: continue
                ContentUris.parseId(uri)
            }
            setReminders(id, reminders)
            ids[key] = id
        }

        // What an earlier sync wrote that no longer exists: a finished task, a
        // deleted goal.
        for ((key, id) in known) {
            if (!ids.containsKey(key)) delete(id)
        }
        return mapOf("calendar" to calendarName, "ids" to ids)
    }

    private fun exists(id: Long): Boolean {
        activity.contentResolver.query(
            Events.CONTENT_URI, arrayOf(Events._ID),
            "${Events._ID} = ? AND ${Events.DELETED} = 0", arrayOf(id.toString()), null,
        )?.use { return it.moveToFirst() }
        return false
    }

    private fun delete(id: Long) {
        activity.contentResolver.delete(ContentUris.withAppendedId(Events.CONTENT_URI, id), null, null)
    }

    private fun setReminders(eventId: Long, minutes: List<Int>) {
        activity.contentResolver.delete(
            Reminders.CONTENT_URI, "${Reminders.EVENT_ID} = ?", arrayOf(eventId.toString()))
        for (m in minutes) {
            activity.contentResolver.insert(Reminders.CONTENT_URI, ContentValues().apply {
                put(Reminders.EVENT_ID, eventId)
                put(Reminders.MINUTES, m)
                put(Reminders.METHOD, Reminders.METHOD_ALERT)
            })
        }
    }

    /**
     * The phone's main calendar: the primary one if it's writable, else a
     * Google one, else any writable one. A phone with none gets a local
     * "StudyTrail" calendar.
     */
    private fun pickCalendar(): Pair<Long, String> {
        var best: Triple<Long, String, Int>? = null
        activity.contentResolver.query(
            Calendars.CONTENT_URI,
            arrayOf(Calendars._ID, Calendars.CALENDAR_DISPLAY_NAME, Calendars.IS_PRIMARY, Calendars.ACCOUNT_TYPE),
            "${Calendars.VISIBLE} = 1 AND ${Calendars.CALENDAR_ACCESS_LEVEL} >= ${Calendars.CAL_ACCESS_CONTRIBUTOR}",
            null, null,
        )?.use { c ->
            while (c.moveToNext()) {
                val score = (if (c.getInt(2) == 1) 2 else 0) +
                    (if (c.getString(3) == "com.google") 1 else 0)
                if (best == null || score > best!!.third) {
                    best = Triple(c.getLong(0), c.getString(1) ?: "Calendar", score)
                }
            }
        }
        best?.let { return it.first to it.second }
        return createLocalCalendar() to "StudyTrail"
    }

    private fun createLocalCalendar(): Long {
        val uri = Calendars.CONTENT_URI.buildUpon()
            .appendQueryParameter(CalendarContract.CALLER_IS_SYNCADAPTER, "true")
            .appendQueryParameter(Calendars.ACCOUNT_NAME, "StudyTrail")
            .appendQueryParameter(Calendars.ACCOUNT_TYPE, CalendarContract.ACCOUNT_TYPE_LOCAL)
            .build()
        val values = ContentValues().apply {
            put(Calendars.ACCOUNT_NAME, "StudyTrail")
            put(Calendars.ACCOUNT_TYPE, CalendarContract.ACCOUNT_TYPE_LOCAL)
            put(Calendars.NAME, "StudyTrail")
            put(Calendars.CALENDAR_DISPLAY_NAME, "StudyTrail")
            put(Calendars.CALENDAR_COLOR, Color.parseColor("#2E63B8"))
            put(Calendars.CALENDAR_ACCESS_LEVEL, Calendars.CAL_ACCESS_OWNER)
            put(Calendars.OWNER_ACCOUNT, "StudyTrail")
            put(Calendars.VISIBLE, 1)
            put(Calendars.SYNC_EVENTS, 1)
            put(Calendars.CALENDAR_TIME_ZONE, TimeZone.getDefault().id)
        }
        val created = activity.contentResolver.insert(uri, values)
            ?: throw NoCalendar("No calendar on this phone can take events")
        return ContentUris.parseId(created)
    }

    private fun day(iso: String): Long =
        SimpleDateFormat("yyyy-MM-dd", Locale.US)
            .apply { timeZone = TimeZone.getTimeZone("UTC") }
            .parse(iso)!!.time

    private class NoCalendar(message: String) : Exception(message)

    companion object {
        private const val REQUEST_CODE = 4521
        private val PERMISSIONS = arrayOf(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR)
    }
}
