import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/models.dart';
import 'app_theme.dart';

/// Maps a badge's DB `icon_key` / `color_key` onto a real icon and palette
/// colour.
///
/// The catalog lives in Postgres, so a badge can be added server-side without
/// an app update — unknown keys fall back to a trophy in the primary accent
/// rather than rendering nothing.
class BadgeStyle {
  const BadgeStyle(this.icon, this.color);

  final IconData icon;
  final Color color;

  static const _icons = <String, IconData>{
    'flag': Symbols.flag,
    'local_fire_department': Symbols.local_fire_department,
    'quiz': Symbols.quiz,
    'style': Symbols.style,
    'nightlight': Symbols.nightlight,
    'dark_mode': Symbols.dark_mode,
    'wb_sunny': Symbols.wb_sunny,
    'self_improvement': Symbols.self_improvement,
    'map': Symbols.map,
    'chat': Symbols.chat,
    'emoji_events': Symbols.emoji_events,
    'rocket_launch': Symbols.rocket_launch,
    'psychology': Symbols.psychology,
    'diamond': Symbols.diamond,
    'task_alt': Symbols.task_alt,
    'timer': Symbols.timer,
    'bolt': Symbols.bolt,
    'whatshot': Symbols.whatshot,
    'library_books': Symbols.library_books,
    'volunteer_activism': Symbols.volunteer_activism,
  };

  static BadgeStyle of(BuildContext context, AchievementBadge badge) {
    final p = context.p;
    final colors = <String, Color>{
      'sky': p.primary,
      'blue': p.primary,
      'cyan': p.primary,
      'violet': p.primary2,
      'indigo': p.primary2,
      'purple': p.primary2,
      'amber': p.amber,
      'gold': p.amber,
      'yellow': p.amber,
      'orange': p.coral,
      'rose': p.coral,
      'red': p.coral,
      'emerald': p.green,
      'green': p.green,
      'teal': p.green,
    };
    return BadgeStyle(
      _icons[badge.iconKey] ?? Symbols.emoji_events,
      colors[badge.colorKey] ?? p.primary,
    );
  }
}
