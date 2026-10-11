import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_theme.dart';

/// Status lines for the common AI jobs, cycled by [AiWorking].
abstract final class WorkingMessages {
  static const quiz = [
    'Reading your material…',
    'Understanding the content…',
    'Crafting smart questions…',
    "Making sure they're tricky…",
    'Almost there…',
  ];
  static const cards = [
    'Reading your material…',
    'Picking key concepts…',
    'Writing front & back…',
    'Polishing the wording…',
    'Almost ready…',
  ];
  static const roadmap = [
    'Reading your syllabus…',
    'Counting the days to your exams…',
    'Splitting units into weeks…',
    'Balancing your pace…',
    'Almost ready…',
  ];
  static const grading = [
    'Reading your answer…',
    'Checking it against your notes…',
    'Marking point by point…',
    'Writing feedback…',
    'Almost done…',
  ];
  static const groupQuiz = [
    'Reading the host’s material…',
    'Writing questions for everyone…',
    'Shuffling the options…',
    'Almost ready…',
  ];
}

/// A long AI job in progress: a pulsing sparkle, a status line that changes
/// every few seconds, and an indeterminate bar. Started as the generator
/// sheet's own progress view; now shared by every screen that waits on Gemini.
class AiWorking extends StatefulWidget {
  const AiWorking({
    super.key,
    this.messages = WorkingMessages.quiz,
    this.hint = 'This can take up to a minute',
    this.icon = Symbols.auto_awesome,
  });

  final List<String> messages;
  final String? hint;
  final IconData icon;

  @override
  State<AiWorking> createState() => _AiWorkingState();
}

class _AiWorkingState extends State<AiWorking>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  Timer? _cycle;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _cycle = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) setState(() => _index++);
    });
  }

  @override
  void dispose() {
    _cycle?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final messages = widget.messages;
    final message =
        messages.isEmpty ? 'Working…' : messages[_index % messages.length];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) => Transform.scale(
            scale: 0.85 + (_pulse.value * 0.3),
            child: Opacity(opacity: 0.6 + (_pulse.value * 0.4), child: child),
          ),
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: p.primarySoft,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(widget.icon, color: p.primary, size: 28, fill: 1),
          ),
        ),
        const SizedBox(height: 16),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 0.3),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: Text(
            message,
            key: ValueKey(message),
            textAlign: TextAlign.center,
            style: TextStyle(
                color: p.ink, fontSize: 14.5, fontWeight: FontWeight.w700),
          ),
        ),
        if (widget.hint != null) ...[
          const SizedBox(height: 8),
          Text(widget.hint!,
              textAlign: TextAlign.center,
              style: TextStyle(color: p.ink3, fontSize: 12)),
        ],
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: 6,
            backgroundColor: p.card2,
            valueColor: AlwaysStoppedAnimation(p.primary),
          ),
        ),
      ],
    );
  }
}

/// Fades and slides its child in once, when it first appears — so something
/// just created arrives in the list instead of popping into place.
///
/// Give it the item's id as its key: an item already on screen keeps its
/// state across rebuilds and doesn't animate again. [index] staggers a list
/// shown for the first time (capped, so a long list doesn't crawl in).
class AppearIn extends StatefulWidget {
  const AppearIn({super.key, required this.child, this.index = 0});

  final Widget child;
  final int index;

  @override
  State<AppearIn> createState() => _AppearInState();
}

class _AppearInState extends State<AppearIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  late final Animation<double> _t =
      CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  Timer? _delay;

  @override
  void initState() {
    super.initState();
    final wait = Duration(milliseconds: 40 * widget.index.clamp(0, 6));
    if (wait == Duration.zero) {
      _c.forward();
    } else {
      _delay = Timer(wait, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _t,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.08), end: Offset.zero)
            .animate(_t),
        child: widget.child,
      ),
    );
  }
}
