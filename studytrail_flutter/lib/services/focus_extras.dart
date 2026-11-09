import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Background noise for a focus block, made on the phone.
enum FocusSound {
  off('Off', 'No sound'),
  pink('Soft noise', 'Even and gentle, like steady rain'),
  brown('Deep noise', 'Low rumble, like a distant waterfall'),
  white('White noise', 'Bright hiss that covers voices');

  const FocusSound(this.label, this.description);
  final String label;
  final String description;

  static FocusSound fromName(String? name) =>
      FocusSound.values.where((s) => s.name == name).firstOrNull ??
      FocusSound.off;
}

/// What a focus block can do to the phone around it: Do Not Disturb and
/// background noise (`FocusExtras.kt`). Android only; a no-op elsewhere and
/// in tests. Never throws — a block mustn't fail over either.
class FocusExtras {
  const FocusExtras();

  static const _channel = MethodChannel('studytrail/focus_extras');

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  /// Whether the student has let the app change Do Not Disturb.
  Future<bool> hasDndAccess() async {
    if (!_supported) return false;
    try {
      return await _channel.invokeMethod<bool>('dndAccess') ?? false;
    } catch (e) {
      debugPrint('DND access check failed: $e');
      return false;
    }
  }

  /// Opens the system page where that access is granted.
  Future<void> openDndSettings() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('openDndSettings');
    } catch (e) {
      debugPrint('Opening DND settings failed: $e');
    }
  }

  /// Silences the phone for the block, or puts its own setting back.
  Future<void> setDnd(bool on) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<bool>('setDnd', {'on': on});
    } catch (e) {
      debugPrint('DND change failed: $e');
    }
  }

  Future<void> playSound(FocusSound sound) async {
    if (!_supported) return;
    try {
      if (sound == FocusSound.off) {
        await _channel.invokeMethod<void>('stopSound');
      } else {
        await _channel.invokeMethod<void>('playSound', {'kind': sound.name});
      }
    } catch (e) {
      debugPrint('Focus sound failed: $e');
    }
  }
}
