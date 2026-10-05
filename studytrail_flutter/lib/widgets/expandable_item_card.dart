import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_theme.dart';

/// A quiz or a deck in a list: tap it and it opens to show what can be done
/// with it — start, retake, delete — and tap again to close.
///
/// The screens keep at most one open at a time, so the list never turns into a
/// wall of buttons.
class ExpandableItemCard extends StatelessWidget {
  const ExpandableItemCard({
    super.key,
    required this.leading,
    required this.title,
    required this.details,
    required this.expanded,
    required this.onToggle,
    required this.actions,
    this.badge,
  });

  final Widget leading;
  final String title;

  /// Lines under the title: counts, last attempt, and so on.
  final List<Widget> details;

  /// Shown at the right of the title row (a due count, a score).
  final Widget? badge;

  final bool expanded;
  final VoidCallback? onToggle;

  /// The buttons revealed when the card opens, side by side.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    // The card colour and shadow are painted by the container; the
    // transparent Material on top of it carries the tap ripple. With the
    // colour on the Material instead, the shadow drew over the card and
    // greyed it.
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: expanded
                ? p.primary.withValues(alpha: 0.45)
                : Colors.transparent,
            width: 1.4,
          ),
          boxShadow: expanded ? p.shadow : p.shadowSm,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(
                    children: [
                      leading,
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: p.ink,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800)),
                            const SizedBox(height: 2),
                            ...details,
                          ],
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        badge!,
                      ],
                      const SizedBox(width: 4),
                      AnimatedRotation(
                        turns: expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                        child: Icon(Symbols.expand_more,
                            color: expanded ? p.primary : p.ink3, size: 24),
                      ),
                    ],
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: expanded
                        ? Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: Row(
                              children: [
                                for (final (i, action) in actions.indexed) ...[
                                  if (i > 0) const SizedBox(width: 10),
                                  Expanded(child: action),
                                ],
                              ],
                            ),
                          )
                        : const SizedBox(width: double.infinity),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One of the buttons inside an open [ExpandableItemCard].
class ItemAction extends StatelessWidget {
  const ItemAction(
    this.label, {
    super.key,
    required this.icon,
    required this.onTap,
    this.danger = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  /// Red, for Delete.
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final bg = danger ? p.errorSoft : p.primary;
    final fg = danger ? p.error : p.onPrimary;
    return Opacity(
      // Faded while it can't be used (busy, or nothing to start).
      opacity: onTap == null ? 0.5 : 1,
      child: _button(bg, fg),
    );
  }

  Widget _button(Color bg, Color fg) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: fg, size: 19, fill: 1),
                const SizedBox(width: 7),
                Text(label,
                    maxLines: 1,
                    style: TextStyle(
                        color: fg, fontSize: 14, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks before deleting. True only when the student taps Delete.
Future<bool> confirmDelete(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final p = context.p;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: p.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      icon: Icon(Symbols.delete, color: p.error, size: 30),
      title: Text(title,
          textAlign: TextAlign.center,
          style: TextStyle(
              color: p.ink, fontSize: 18, fontWeight: FontWeight.w800)),
      content: Text(message,
          textAlign: TextAlign.center,
          style: TextStyle(color: p.ink2, fontSize: 14, height: 1.45)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text('Cancel', style: TextStyle(color: p.ink3)),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text('Delete',
              style: TextStyle(color: p.error, fontWeight: FontWeight.w800)),
        ),
      ],
    ),
  );
  return confirmed == true;
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// When something happened, in the phone's time: "Today, 3:42 PM",
/// "Yesterday, 9:05 AM", "Mon, 29 Sep, 6:10 PM", or with the year once it's
/// a different one. [now] is a parameter so the wording can be tested.
String whenLabel(DateTime at, DateTime now) {
  final local = at.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final time = '$hour:${local.minute.toString().padLeft(2, '0')} '
      '${local.hour < 12 ? 'AM' : 'PM'}';
  final day = DateTime(local.year, local.month, local.day);
  final today = DateTime(now.year, now.month, now.day);
  // Rounded hours, not inDays: a day with a clock change is 23 or 25 hours.
  final daysAgo = (today.difference(day).inHours / 24).round();
  final date = switch (daysAgo) {
    0 => 'Today',
    1 => 'Yesterday',
    _ when local.year == now.year =>
      '${_weekdays[local.weekday - 1]}, ${local.day} ${_months[local.month - 1]}',
    _ => '${local.day} ${_months[local.month - 1]} ${local.year}',
  };
  return '$date, $time';
}
