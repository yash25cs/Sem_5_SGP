import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// What the app shows while it works out where to land: the logo settling in,
/// a trail circling it, and the wordmark rising underneath.
///
/// The trail is the logo's own idea — a dotted path rising out of a book — so
/// the loading ring is drawn in the logo's teal and indigo with a dot at its
/// head. With the system's "remove animations" setting on, it all sits still.
class LaunchSplash extends StatefulWidget {
  const LaunchSplash({super.key});

  @override
  State<LaunchSplash> createState() => _LaunchSplashState();
}

class _LaunchSplashState extends State<LaunchSplash>
    with TickerProviderStateMixin {
  /// The colours of the logo itself, not the theme's.
  static const _teal = Color(0xFF1FB8C9);
  static const _indigo = Color(0xFF4A50AC);

  static const _logoSize = 112.0;
  static const _ringSize = 156.0;

  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..forward();

  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  late final Animation<double> _logoScale = Tween(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
          parent: _intro,
          curve: const Interval(0, 0.65, curve: Curves.easeOutBack)));
  late final Animation<double> _logoFade = CurvedAnimation(
      parent: _intro, curve: const Interval(0, 0.35, curve: Curves.easeOut));
  late final Animation<double> _ringFade = CurvedAnimation(
      parent: _intro, curve: const Interval(0.3, 0.75, curve: Curves.easeOut));
  late final Animation<double> _wordFade = CurvedAnimation(
      parent: _intro, curve: const Interval(0.45, 1, curve: Curves.easeOut));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (still) {
      _intro.value = 1;
      _loop.stop();
    } else if (!_loop.isAnimating) {
      _loop.repeat();
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Scaffold(
      backgroundColor: p.bg,
      body: Semantics(
        label: 'Loading StudyTrail',
        child: Center(
          child: AnimatedBuilder(
            animation: Listenable.merge([_intro, _loop]),
            builder: (context, _) {
              final wave = math.sin(_loop.value * 2 * math.pi);
              // A slow breath once the logo has landed.
              final breath = 1 + 0.025 * wave * _ringFade.value;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: _ringSize,
                    height: _ringSize,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Soft light behind the logo, pulsing with the breath.
                        Opacity(
                          opacity: _logoFade.value,
                          child: Container(
                            width: _logoSize,
                            height: _logoSize,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: _indigo.withValues(
                                      alpha: 0.22 + 0.08 * wave),
                                  blurRadius: 40 + 14 * wave,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        ),
                        Opacity(
                          opacity: _ringFade.value,
                          child: CustomPaint(
                            size: const Size.square(_ringSize),
                            painter: _TrailPainter(
                              turn: _loop.value,
                              track: p.line,
                              head: _teal,
                              tail: _indigo,
                            ),
                          ),
                        ),
                        Opacity(
                          opacity: _logoFade.value,
                          child: Transform.scale(
                            scale: _logoScale.value * breath,
                            child: const _Logo(size: _logoSize),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  Opacity(
                    opacity: _wordFade.value,
                    child: Transform.translate(
                      offset: Offset(0, 14 * (1 - _wordFade.value)),
                      child: Column(
                        children: [
                          Text.rich(
                            TextSpan(children: [
                              TextSpan(
                                  text: 'Study',
                                  style: TextStyle(color: p.primary2)),
                              TextSpan(
                                  text: 'Trail',
                                  style: TextStyle(color: p.ink)),
                            ]),
                            style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.7),
                          ),
                          const SizedBox(height: 6),
                          Text('Your study plan, one step at a time',
                              style: TextStyle(
                                  color: p.ink3,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The logo, cropped to its white rounded tile.
///
/// The image file carries a light grey margin around the tile, which shows up
/// as a pale square on the dark theme; scaling it inside the clip leaves just
/// the tile.
class _Logo extends StatelessWidget {
  const _Logo({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size * 0.24),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.24),
        child: Transform.scale(
          scale: 1.3,
          child: Image.asset(
            'assets/images/studytrail_logo.jpg',
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
          ),
        ),
      ),
    );
  }
}

/// A faint circular track with a comet-like arc running round it: indigo at
/// the tail, teal at the head, and a dot leading — the logo's path, moving.
class _TrailPainter extends CustomPainter {
  _TrailPainter({
    required this.turn,
    required this.track,
    required this.head,
    required this.tail,
  });

  /// 0–1, one full lap.
  final double turn;
  final Color track;
  final Color head;
  final Color tail;

  static const _sweep = math.pi * 0.75;
  static const _stroke = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - _stroke;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = track.withValues(alpha: 0.6),
    );

    final start = turn * 2 * math.pi - math.pi / 2;
    // The gradient is drawn in the arc's own frame, so it rotates with it.
    final shader = SweepGradient(
      startAngle: 0,
      endAngle: _sweep,
      colors: [tail.withValues(alpha: 0), tail, head],
      stops: const [0, 0.55, 1],
      transform: GradientRotation(start),
    ).createShader(rect);

    canvas.drawArc(
      rect,
      start,
      _sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..strokeCap = StrokeCap.round
        ..shader = shader,
    );

    final tip = start + _sweep;
    final dot = center + Offset(math.cos(tip), math.sin(tip)) * radius;
    canvas.drawCircle(dot, _stroke * 1.6, Paint()..color = head);
    canvas.drawCircle(dot, _stroke * 0.7,
        Paint()..color = Colors.white.withValues(alpha: 0.9));
  }

  @override
  bool shouldRepaint(_TrailPainter old) =>
      old.turn != turn ||
      old.track != track ||
      old.head != head ||
      old.tail != tail;
}
