import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The signature OneKit background: monochrome stars drifting downward, each
/// breathing on its own phase so the whole field pulses without ever syncing up.
///
/// The painter is driven by a single controller and wrapped in a
/// [RepaintBoundary], so it repaints in isolation from the page content.
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

class _StarfieldState extends State<Starfield> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  List<_Star> _stars = const [];
  Size _lastSize = Size.zero;

  /// Smoothed speed so changes (idle -> converting) ease instead of snapping.
  double _speed = 1.0;

  @override
  void initState() {
    super.initState();
    _speed = widget.speed;
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 60))..repeat();
  }

  @override
  void didUpdateWidget(covariant Starfield old) {
    super.didUpdateWidget(old);
    if (old.density != widget.density) _lastSize = Size.zero;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _ensureStars(Size size) {
    if (size == _lastSize || size.isEmpty) return;
    _lastSize = size;
    final area = size.width * size.height;
    // ~1 star per 5200 logical px², clamped so phones and tablets both feel right.
    final count = (area / 5200 * widget.density).round().clamp(28, 160);
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
    // Ease toward the requested speed on every frame the widget rebuilds.
    _speed = _speed + (widget.speed - _speed) * 0.25;

    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: LayoutBuilder(
            builder: (context, constraints) {
              _ensureStars(constraints.biggest);
              return AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => CustomPaint(
                  size: constraints.biggest,
                  painter: _StarfieldPainter(
                    stars: _stars,
                    time: _controller.value * 60,
                    color: t.starColor,
                    speed: _speed,
                  ),
                ),
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

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    for (final s in stars) {
      // Wrap vertically so the field never runs out of stars.
      final y = ((s.y + time * s.fall * speed) % 1.0) * size.height;
      final x = s.x * size.width;

      final twinkle = 0.5 + 0.5 * math.sin(time * s.twinkleRate + s.twinklePhase);
      final opacity = (0.10 + 0.55 * twinkle) * (0.35 + s.depth * 0.65);
      final r = s.radius * (0.82 + 0.28 * twinkle);

      paint.color = color.withValues(alpha: opacity.clamp(0.0, 1.0));

      if (s.streak && speed > 1.4) {
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

      // A soft halo on the nearest stars gives the field depth.
      if (s.depth > 0.7) {
        paint.color = color.withValues(alpha: (opacity * 0.16).clamp(0.0, 1.0));
        canvas.drawCircle(Offset(x, y), r * 3.4, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_StarfieldPainter old) =>
      old.time != time || old.color != color || old.speed != speed || old.stars != stars;
}
