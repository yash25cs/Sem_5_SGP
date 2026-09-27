import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../state/home_store.dart';
import '../theme/app_theme.dart';
import 'common.dart';

class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    final homeStore = context.watch<HomeStore>();
    final p = context.p;
    
    // Generate alerts
    final List<_Alert> alerts = [];
    
    final streak = homeStore.streak.currentStreak;
    final done = homeStore.doneCount;
    final total = homeStore.tasks.length;
    final goal = homeStore.goal;

    if (streak > 0 && done == 0) {
      alerts.add(_Alert(
        icon: Symbols.local_fire_department,
        title: 'Streak at risk!',
        subtitle: 'Complete a task today to keep your $streak-day streak alive.',
        color: const Color(0xFFFFC773),
      ));
    } else if (total > 0 && done == total) {
      alerts.add(_Alert(
        icon: Symbols.celebration,
        title: 'All done!',
        subtitle: 'You completed all $total tasks today. Great job!',
        color: p.green,
      ));
    }

    if (goal != null && goal.daysLeft != null) {
      if (goal.daysLeft! <= 7 && goal.daysLeft! > 0) {
        alerts.add(_Alert(
          icon: Symbols.timer,
          title: 'Exam approaching',
          subtitle: 'Only ${goal.daysLeft} days left until your exam!',
          color: p.error,
        ));
      } else if (goal.daysLeft! == 0) {
        alerts.add(_Alert(
          icon: Symbols.warning,
          title: 'Exam day!',
          subtitle: 'Good luck! You got this.',
          color: p.error,
        ));
      }
    }

    final hasAlerts = alerts.isNotEmpty;

    return Stack(
      children: [
        RoundIconButton(
          Symbols.notifications,
          plain: false,
          onTap: () {
            showModalBottomSheet(
              context: context,
              backgroundColor: p.bg,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              builder: (context) => _AlertsSheet(alerts: alerts),
            );
          },
        ),
        if (hasAlerts)
          Positioned(
            top: 2,
            right: 2,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: p.error,
                shape: BoxShape.circle,
                border: Border.all(color: p.card, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}

class _Alert {
  const _Alert({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
}

class _AlertsSheet extends StatelessWidget {
  const _AlertsSheet({required this.alerts});
  final List<_Alert> alerts;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Notifications',
                style: TextStyle(
                    color: p.ink, fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            if (alerts.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text("You're all caught up!",
                      style: TextStyle(color: p.ink2, fontSize: 16)),
                ),
              )
            else
              ...alerts.map((a) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: a.color.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(a.icon, color: a.color, size: 24, fill: 1),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(a.title,
                                  style: TextStyle(
                                      color: p.ink,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 4),
                              Text(a.subtitle,
                                  style: TextStyle(
                                      color: p.ink2, fontSize: 14, height: 1.4)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}
