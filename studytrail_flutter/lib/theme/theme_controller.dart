import 'package:flutter/material.dart';

import '../data/local_prefs.dart';

/// Holds the app-wide light/dark mode and lets any widget flip it.
///
/// The choice is remembered on the device. It used to live only in memory, so
/// every launch reset a student's dark mode back to light.
class ThemeController extends ChangeNotifier {
  ThemeController() {
    _restore();
  }

  ThemeMode _mode = ThemeMode.light;
  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;

  /// Set once the student picks a mode, so a slow read of the saved value
  /// can't overwrite a choice made in the meantime.
  bool _touched = false;

  Future<void> _restore() async {
    final dark = await LocalPrefs.darkMode();
    if (_touched || dark == isDark) return;
    _mode = dark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  void toggle() => set(!isDark);

  void set(bool dark) {
    _touched = true;
    _mode = dark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
    LocalPrefs.setDarkMode(dark);
  }
}
