import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_theme.dart';

/// The five-item bottom navigation bar from the reference. Rounded top, active
/// item is a filled indigo pill.
class BottomNav extends StatelessWidget {
  const BottomNav({super.key, required this.current, this.onTap});

  /// Index of the active destination (0=Home … 4=Profile).
  final int current;
  final ValueChanged<int>? onTap;

  static const _items = [
    (Symbols.home, 'Home'),
    (Symbols.calendar_month, 'Roadmap'),
    (Symbols.smart_toy, 'Chat'),
    (Symbols.quiz, 'Quiz'),
    (Symbols.person, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Container(
      decoration: BoxDecoration(
        color: p.card,
        border: Border(top: BorderSide(color: p.line)),
      ),
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 10),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            for (var i = 0; i < _items.length; i++)
              _NavItem(
                icon: _items[i].$1,
                label: _items[i].$2,
                active: i == current,
                onTap: () => onTap?.call(i),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem(
      {required this.icon, required this.label, required this.active, this.onTap});
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final fg = active ? p.onPrimary : p.ink3;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? p.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24, color: fg, fill: active ? 1 : 0, weight: active ? 600 : 500),
            const SizedBox(height: 3),
            Text(label,
                style: TextStyle(
                    fontSize: 10.5, fontWeight: FontWeight.w700, color: fg)),
          ],
        ),
      ),
    );
  }
}

/// Vertical room for the device's own status bar.
///
/// This replaced a `StatusStrip` widget that painted a fake `9:41` plus signal,
/// wifi and battery icons — carried over from the HTML mock, where the phone
/// chrome had to be drawn. On a real device it collided with the actual system
/// clock. That strip was also the only thing keeping screen content clear of
/// the system bar, so the inset it supplied has to stay behind.
///
/// [MediaQuery.paddingOf] rather than a fixed height, so notches and punch-hole
/// cameras get the space they need. Under the focus-session bar the surrounding
/// [MediaQuery] has its top padding removed, which collapses this to [extra] —
/// the bar has already paid the inset.
class TopInset extends StatelessWidget {
  const TopInset({super.key, this.extra = 8});

  /// Breathing room below the system bar. The old strip's padding worked out to
  /// roughly this much.
  final double extra;

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: MediaQuery.paddingOf(context).top + extra);
}
