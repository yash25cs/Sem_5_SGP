import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../data/local_prefs.dart';
import '../state/reminder_sync.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// 1080 → "6:00 PM", in the phone's own 12/24-hour style.
String reminderTimeLabel(BuildContext context, int minute) =>
    TimeOfDay(hour: minute ~/ 60, minute: minute % 60).format(context);

/// Asks for a new daily reminder time, saves it, and reschedules. Returns the
/// minute picked, or null if the picker was dismissed.
Future<int?> pickReminderTime(BuildContext context, int current) async {
  final picked = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
    helpText: 'Daily study reminder',
  );
  if (picked == null) return null;
  final minute = picked.hour * 60 + picked.minute;
  await LocalPrefs.setReminderMinute(minute);
  await LocalPrefs.setRemindersEnabled(true);
  await ReminderSync.run(askPermission: true);
  return minute;
}

/// The reminder time as a card, for onboarding: when to be nudged to study,
/// with a switch to turn it off.
class ReminderTimeCard extends StatefulWidget {
  const ReminderTimeCard({super.key});

  @override
  State<ReminderTimeCard> createState() => _ReminderTimeCardState();
}

class _ReminderTimeCardState extends State<ReminderTimeCard> {
  int _minute = LocalPrefs.defaultReminderMinute;
  bool _on = true;

  @override
  void initState() {
    super.initState();
    Future.wait([LocalPrefs.reminderMinute(), LocalPrefs.remindersEnabled()])
        .then((r) {
      if (!mounted) return;
      setState(() {
        _minute = r[0] as int;
        _on = r[1] as bool;
      });
    });
  }

  Future<void> _change() async {
    final minute = await pickReminderTime(context, _minute);
    if (minute == null || !mounted) return;
    setState(() {
      _minute = minute;
      _on = true;
    });
  }

  Future<void> _toggle(bool on) async {
    setState(() => _on = on);
    await LocalPrefs.setRemindersEnabled(on);
    await ReminderSync.run(askPermission: on);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          IconTile(Symbols.notifications,
              bg: p.coralSoft, fg: p.coral, size: 40, radius: 12),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              key: const ValueKey('reminder-time'),
              onTap: _change,
              borderRadius: BorderRadius.circular(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Daily study reminder',
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(
                      _on
                          ? 'Every day at ${reminderTimeLabel(context, _minute)} · tap to change'
                          : 'Off',
                      style: TextStyle(color: p.ink2, fontSize: 12.5)),
                ],
              ),
            ),
          ),
          Switch(value: _on, onChanged: _toggle),
        ],
      ),
    );
  }
}
