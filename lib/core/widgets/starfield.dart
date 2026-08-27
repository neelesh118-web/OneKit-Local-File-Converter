import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/settings_store.dart';
import '../theme/app_theme.dart';

/// The signature OneKit background: monochrome stars drifting downward, each
/// breathing on its own phase so the whole field pulses without ever syncing up.
///
/// It repaints on every frame by construction, so it is deliberately cheap:
/// one reused [Paint], a precomputed colour ramp instead of a per-star alpha
/// blend, and a single draw call per star. It also stops itself when it is not
/// being looked at — covered by another route, or the app in the background.
class Starfield extends StatefulWidget {
  const Starfield({
    super.key,
    this.density = 1.0,
    this.speed = 1.0,
    this.child,
  });

  /// Multiplier on the star count. Kept low on small screens automatically.
  final double density;

  /// Multiplier on fall speed. The convert screen raises this while working.
  final double speed;

  final Widget? child;

  @override
  State<Starfield> createState() => _StarfieldState();
}

class _StarfieldState extends State<Starfield>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;
  List<_Star> _stars = const [];
  Size _lastSize = Size.zero;

  /// Smoothed speed so changes (idle -> converting) ease instead of snapping.
  double _speed = 1.0;

  /// Reasons the field is currently not worth animating.
  bool _backgrounded = false;
  bool _covered = false;

  @override
  void initState() {
    super.initState();
    _speed = widget.speed;
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 60))
      ..repeat();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant Starfield old) {
    super.didUpdateWidget(old);
    if (old.density != widget.density) _lastSize = Size.zero;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _backgrounded = state != AppLifecycleState.resumed;
    _syncRunning();
  }

  /// Runs the controller only while the field can actually be seen. A stopped
  /// controller schedules no frames at all, which is the whole point.
  void _syncRunning() {
    final shouldRun = !_backgrounded && !_covered;
    if (shouldRun && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!shouldRun && _controller.isAnimating) {
      _controller.stop(canceled: false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  /// Eases the field toward the requested speed, once per frame.
  void _tickSpeed() {
    final target = widget.speed;
    if ((target - _speed).abs() < 0.005) {
      _speed = target;
      return;
    }
    _speed += (target - _speed) * 0.06;
  }

  void _ensureStars(Size size) {
    if (size == _lastSize || size.isEmpty) return;
    _lastSize = size;
    final area = size.width * size.height;
    // ~1 star per 6000 logical px², clamped so phones and tablets both feel
    // right. The ceiling is what bounds the per-frame draw cost.
    final count = (area / 6000 * widget.density).round().clamp(24, 110);
    final rnd = math.Random(20260826);
    _stars = List.generate(count, (i) {
      final depth = rnd.nextDouble(); // 0 = far/slow/small, 1 = near/fast/big
      return _Star(
        x: rnd.nextDouble(),
        y: rnd.nextDouble(),
        depth: depth,
        radius: 0.5 + depth * 1.9,
        fall: 0.012 + depth * 0.055,
        twinklePhase: rnd.nextDouble() * math.pi * 2,
        twinkleRate: 0.5 + rnd.nextDouble() * 1.6,
        streak: depth > 0.82,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    // Honoured here rather than at each call site: the splash, pairs and about
    // screens each built their own field and silently ignored the setting.
    if (!context.select<SettingsStore, bool>((s) => s.starfieldEnabled)) {
      return widget.child ?? const SizedBox.shrink();
    }

    // A route pushed on top of this one means the field is not visible; the
    // shell's field would otherwise keep animating behind every pushed page.
    final covered = ModalRoute.of(context)?.isCurrent == false;
    if (covered != _covered) {
      _covered = covered;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncRunning();
      });
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: LayoutBuilder(
            builder: (context, constraints) {
              _ensureStars(constraints.biggest);
              return AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  _tickSpeed();
                  return CustomPaint(
                    size: constraints.biggest,
                    painter: _StarfieldPainter(
                      stars: _stars,
                      time: _controller.value * 60,
                      color: t.starColor,
                      speed: _speed,
                    ),
                  );
                },
              );
            },
          ),
        ),
        if (widget.child != null) widget.child!,
      ],
    );
  }
}

class _Star {
  const _Star({
    required this.x,
    required this.y,
    required this.depth,
    required this.radius,
    required this.fall,
    required this.twinklePhase,
    required this.twinkleRate,
    required this.streak,
  });

  final double x;
  final double y;
  final double depth;
  final double radius;
  final double fall;
  final double twinklePhase;
  final double twinkleRate;
  final bool streak;
}

class _StarfieldPainter extends CustomPainter {
  _StarfieldPainter({
    required this.stars,
    required this.time,
    required this.color,
    required this.speed,
  });

  final List<_Star> stars;
  final double time;
  final Color color;
  final double speed;

  /// Alpha is quantised into this many steps and the colours cached, so a
  /// frame does lookups instead of ~100 Color blends.
  static const _rampSteps = 24;
  static Color? _rampColor;
  static late List<Color> _ramp;

  static List<Color> _rampFor(Color c) {
    if (_rampColor == c) return _ramp;
    _rampColor = c;
    _ramp = List<Color>.generate(
      _rampSteps,
      (i) => c.withValues(alpha: (i + 1) / _rampSteps * 0.68),
    );
    return _ramp;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final ramp = _rampFor(color);
    final streaking = speed > 1.4;

    for (final s in stars) {
      // Wrap vertically so the field never runs out of stars.
      final y = ((s.y + time * s.fall * speed) % 1.0) * size.height;
      final x = s.x * size.width;

      final twinkle = 0.5 + 0.5 * math.sin(time * s.twinkleRate + s.twinklePhase);
      final opacity = (0.10 + 0.55 * twinkle) * (0.35 + s.depth * 0.65);
      final r = s.radius * (0.82 + 0.28 * twinkle);

      paint.color = ramp[(opacity * _rampSteps).clamp(0, _rampSteps - 1).toInt()];

      if (s.streak && streaking) {
        // Fast foreground stars stretch into short trails while converting.
        final tail = r * 6 * (speed - 1.0);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x - r, y - tail, r * 2, tail + r * 2),
            Radius.circular(r),
          ),
          paint,
        );
      } else {
        canvas.drawCircle(Offset(x, y), r, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_StarfieldPainter old) =>
      old.time != time || old.color != color || old.speed != speed || old.stars != stars;
}
