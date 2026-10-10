import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// Asks how long the student wants to study each day, from 15 minutes to 10
/// hours. Returns the minutes, or null if dismissed. Used by the goal form
/// and by Settings → Pace.
Future<int?> showCustomPaceSheet(BuildContext context, {int? initial}) {
  final p = context.p;
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (_) => _CustomPaceSheet(initial: initial ?? 90),
  );
}

class _CustomPaceSheet extends StatefulWidget {
  const _CustomPaceSheet({required this.initial});
  final int initial;

  @override
  State<_CustomPaceSheet> createState() => _CustomPaceSheetState();
}

class _CustomPaceSheetState extends State<_CustomPaceSheet> {
  /// 15-minute steps up to two hours, then half-hours: a student choosing
  /// 45 minutes cares about the quarter, one choosing 6 hours doesn't.
  static final _steps = [
    for (var m = 15; m <= 120; m += 15) m,
    for (var m = 150; m <= 600; m += 30) m,
  ];

  late int _index;

  @override
  void initState() {
    super.initState();
    _index = _nearestIndex(widget.initial);
  }

  static int _nearestIndex(int minutes) {
    var best = 0;
    for (final (i, m) in _steps.indexed) {
      if ((m - minutes).abs() < (_steps[best] - minutes).abs()) best = i;
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final minutes = _steps[_index];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your own pace',
                style: TextStyle(
                    color: p.ink, fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('How long can you study on a normal day? Your roadmap is '
                'sized to it.',
                style: TextStyle(color: p.ink2, fontSize: 13, height: 1.45)),
            const SizedBox(height: 22),
            Center(
              child: Text('${formatStudyTime(minutes)} a day',
                  key: const ValueKey('custom-pace-value'),
                  style: TextStyle(
                      color: p.primary,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5)),
            ),
            Slider(
              value: _index.toDouble(),
              min: 0,
              max: (_steps.length - 1).toDouble(),
              divisions: _steps.length - 1,
              label: formatStudyTime(minutes),
              onChanged: (v) => setState(() => _index = v.round()),
            ),
            Row(
              children: [
                Text('15 min', style: TextStyle(color: p.ink3, fontSize: 12)),
                const Spacer(),
                Text('10 hrs', style: TextStyle(color: p.ink3, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 18),
            PillButton('Use ${formatStudyTime(minutes)} a day',
                icon: Symbols.check,
                onTap: () => Navigator.of(context).pop(minutes)),
          ],
        ),
      ),
    );
  }
}
