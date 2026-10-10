import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// Device-local flags that outlive a launch but aren't worth a server round
/// trip.
///
/// Anything the student owns belongs in Postgres. This is only for facts about
/// *this install* — whether the welcome tour has been seen, how they like their
/// focus timer set up — which shouldn't follow the account onto a different
/// phone.
class LocalPrefs {
  const LocalPrefs._();

  /// Versioned so a reworked tour can be shown again without colliding with
  /// the value already on device.
  static const String _seenWelcomeKey = 'seen_welcome_v1';
  static const String _timerPresetsKey = 'timer_presets_v1';
  static const String _activeTimerKey = 'timer_active_v1';

  /// False on a fresh install, which is what puts the tour on screen.
  ///
  /// A failed read also reports false: if the preference store is unavailable,
  /// showing the tour again is a minor annoyance the student can skip, whereas
  /// reporting true would silently swallow first-run onboarding. Same reasoning
  /// as the `hasAnyGoal` fallback in `RootFlow._resolveEntryStage`.
  static Future<bool> hasSeenWelcome() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_seenWelcomeKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setSeenWelcome() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_seenWelcomeKey, true);
    } catch (_) {
      // Non-fatal: the worst outcome is the tour showing once more next launch.
    }
  }

  /// The student's own focus-timer presets. Built-ins aren't stored — they ship
  /// with the app, so persisting them would freeze whatever values were current
  /// at install time.
  ///
  /// Unreadable entries are skipped rather than failing the list: one bad row
  /// from an older build shouldn't cost the student every preset they saved.
  static Future<List<TimerPreset>> getTimerPresets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_timerPresetsKey);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final entry in decoded) ?TimerPreset.fromJson(entry),
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> setTimerPresets(List<TimerPreset> presets) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _timerPresetsKey,
        jsonEncode([for (final p in presets) p.toJson()]),
      );
    } catch (_) {
      // Non-fatal: the preset still applies to this run, it just won't survive
      // a restart.
    }
  }

  /// Id of the preset the timer was last set to, or null if it was never
  /// changed or the store couldn't be read.
  static Future<String?> getActiveTimerId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_activeTimerKey);
    } catch (_) {
      return null;
    }
  }

  static Future<void> setActiveTimerId(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_activeTimerKey, id);
    } catch (_) {
      // Non-fatal: next launch falls back to the default preset.
    }
  }

  // Rewards used to be stored here (`unlocked_rewards_v1`,
  // `spent_rewards_xp_v1`). They moved to the server in 0012 because a
  // purchase belongs to the student, not the phone; the stale keys are
  // harmless and simply never read again.

  static const String _darkModeKey = 'dark_mode_v1';

  /// Light unless the student switched to dark on this device.
  static Future<bool> darkMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_darkModeKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setDarkMode(bool dark) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_darkModeKey, dark);
    } catch (_) {
      // Non-fatal: the mode still applies for this run.
    }
  }

  static const String _remindersKey = 'daily_reminder_enabled_v1';

  /// Whether the 6 PM study reminder is on. Defaults to on, which is what the
  /// app did before the Settings switch was wired up.
  static Future<bool> remindersEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_remindersKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> setRemindersEnabled(bool on) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_remindersKey, on);
    } catch (_) {
      // Non-fatal: the schedule itself was already changed.
    }
  }

  static const String _reminderTimeKey = 'daily_reminder_minute_v1';

  /// When the daily study reminder fires, as minutes after midnight. 6 PM
  /// until the student picks a time.
  static const int defaultReminderMinute = 18 * 60;

  static Future<int> reminderMinute() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getInt(_reminderTimeKey);
      return v == null || v < 0 || v >= 24 * 60 ? defaultReminderMinute : v;
    } catch (_) {
      return defaultReminderMinute;
    }
  }

  static Future<void> setReminderMinute(int minute) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_reminderTimeKey, minute);
    } catch (_) {
      // Non-fatal: this run's schedule already uses it.
    }
  }

  static const String _calendarSyncKey = 'calendar_sync_v1';
  static const String _calendarEventsKey = 'calendar_events_v1';

  /// Whether exams and the plan are kept in the phone's calendar.
  static Future<bool> calendarSync() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_calendarSyncKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setCalendarSync(bool on) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_calendarSyncKey, on);
    } catch (_) {}
  }

  /// The calendar events StudyTrail wrote, by its own id for each, so a later
  /// sync updates or removes them instead of adding copies.
  static Future<Map<String, int>> calendarEvents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_calendarEventsKey);
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final e in decoded.entries)
          if (e.value is num) e.key as String: (e.value as num).toInt(),
      };
    } catch (_) {
      return {};
    }
  }

  static Future<void> setCalendarEvents(Map<String, int> events) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_calendarEventsKey, jsonEncode(events));
    } catch (_) {}
  }
}
