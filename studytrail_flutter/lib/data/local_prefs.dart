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

  static const String _unlockedRewardsKey = 'unlocked_rewards_v1';
  static const String _spentXpKey = 'spent_rewards_xp_v1';

  static Future<List<String>> getUnlockedRewards() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_unlockedRewardsKey) ?? [];
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveUnlockedReward(String id, int costXp) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = prefs.getStringList(_unlockedRewardsKey) ?? [];
      if (!current.contains(id)) {
        current.add(id);
        await prefs.setStringList(_unlockedRewardsKey, current);
      }
      final spent = prefs.getInt(_spentXpKey) ?? 0;
      await prefs.setInt(_spentXpKey, spent + costXp);
    } catch (_) {}
  }

  static Future<int> getSpentRewardXp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_spentXpKey) ?? 0;
    } catch (_) {
      return 0;
    }
  }
}
