import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_theme.dart';
import 'common.dart';

/// One entry in the quick-actions sheet.
class QuickAction {
  const QuickAction({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;

  /// Only the featured card shows one; grid tiles stay a single label.
  final String? subtitle;
}

/// The + button's sheet: one featured action, then labelled groups laid out
/// as a three-column grid.
///
/// Replaces a single list of ten rows that ran the full height of the screen.
class QuickActionsSheet extends StatelessWidget {
  const QuickActionsSheet({
    super.key,
    required this.featured,
    required this.sections,
  });

  final QuickAction featured;
  final List<(String, List<QuickAction>)> sections;

  static const _columns = 3;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(28),
        boxShadow: p.shadow,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: p.line2, borderRadius: BorderRadius.circular(99)),
                ),
              ),
              const SizedBox(height: 16),
              Text('Quick actions',
                  style: TextStyle(
                      color: p.ink, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              _FeaturedCard(action: featured),
              for (final (label, actions) in sections) ...[
                const SizedBox(height: 18),
                Text(label.toUpperCase(),
                    style: TextStyle(
                        color: p.ink3,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8)),
                const SizedBox(height: 10),
                for (var i = 0; i < actions.length; i += _columns) ...[
                  if (i > 0) const SizedBox(height: 10),
                  // Equal-height tiles even when one title wraps to two lines.
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var j = i; j < i + _columns; j++) ...[
                          if (j > i) const SizedBox(width: 10),
                          Expanded(
                            child: j < actions.length
                                ? _Tile(action: actions[j])
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({required this.action});

  final QuickAction action;

  @override
  Widget build(BuildContext context) {
    final c = action.color;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              colors: [c, Color.lerp(c, Colors.black, 0.18)!],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(action.icon, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(action.title,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800)),
                    if (action.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(action.subtitle!,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 12.5)),
                    ],
                  ],
                ),
              ),
              const Icon(Symbols.arrow_forward, color: Colors.white, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.action});

  final QuickAction action;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          decoration: BoxDecoration(
            color: p.card2,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconTile(action.icon,
                  bg: action.color.withValues(alpha: 0.16),
                  fg: action.color,
                  size: 44,
                  radius: 14),
              const SizedBox(height: 8),
              Text(action.title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      height: 1.25)),
            ],
          ),
        ),
      ),
    );
  }
}
