import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A breathing halo used behind the logo and the convert button.
///
/// It pulses purely for atmosphere and carries no progress meaning — the ring
/// in [PulseProgress] is the one that reports real numbers.
class PulseHalo extends StatefulWidget {
  const PulseHalo({
    super.key,
    required this.child,
    this.size = 140,
    this.rings = 3,
    this.period = const Duration(milliseconds: 2600),
    this.active = true,
  });

  final Widget child;
  final double size;
  final int rings;
  final Duration period;
  final bool active;

  @override
  State<PulseHalo> createState() => _PulseHaloState();
}

class _PulseHaloState extends State<PulseHalo> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.period)..repeat();

  @override
  void didUpdateWidget(covariant PulseHalo old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.active && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) => CustomPaint(
                size: Size.square(widget.size),
                painter: _HaloPainter(_c.value, widget.rings, t.accent),
              ),
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}

class _HaloPainter extends CustomPainter {
  _HaloPainter(this.t, this.rings, this.color);
  final double t;
  final int rings;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxR = size.shortestSide / 2;
    final paint = Paint()..style = PaintingStyle.stroke;

    for (var i = 0; i < rings; i++) {
      // Each ring is offset in phase so they emanate one after another.
      final phase = (t + i / rings) % 1.0;
      final eased = Curves.easeOutCubic.transform(phase);
      final r = maxR * (0.42 + eased * 0.58);
      final fade = (1.0 - phase) * 0.5;
      if (fade <= 0.01) continue;
      paint
        ..color = color.withValues(alpha: fade.clamp(0.0, 1.0))
        ..strokeWidth = 1.4 + (1 - phase) * 1.6;
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(_HaloPainter old) => old.t != t || old.color != color;
}

/// The conversion dial: a real progress arc wrapped in pulses whose energy
/// tracks the actual percentage, plus a live percentage readout.
class PulseProgress extends StatefulWidget {
  const PulseProgress({
    super.key,
    required this.progress,
    this.size = 200,
    this.label,
    this.indeterminate = false,
  });

  /// 0.0 - 1.0. Real progress reported by the engine, never a fake timer.
  final double progress;
  final double size;
  final String? label;

  /// Set while the engine cannot report a percentage (e.g. probing a file).
  final bool indeterminate;

  @override
  State<PulseProgress> createState() => _PulseProgressState();
}

class _PulseProgressState extends State<PulseProgress> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat();

  /// Progress is smoothed so ffmpeg's chunky updates render as a fluid sweep.
  double _shown = 0;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final target = widget.progress.clamp(0.0, 1.0);

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          _shown += (target - _shown) * 0.18;
          if ((target - _shown).abs() < 0.0015) _shown = target;
          final pct = (_shown * 100);

          return SizedBox(
            width: widget.size,
            height: widget.size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: Size.square(widget.size),
                  painter: _DialPainter(
                    progress: _shown,
                    t: _c.value,
                    color: t.accent,
                    track: t.border,
                    indeterminate: widget.indeterminate,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.indeterminate ? '—' : '${pct.toStringAsFixed(pct >= 99.5 ? 0 : 1)}%',
                      style: TextStyle(
                        fontSize: widget.size * 0.19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.5,
                        color: t.textPrimary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (widget.label != null) ...[
                      const SizedBox(height: 4),
                      SizedBox(
                        width: widget.size * 0.72,
                        child: Text(
                          widget.label!,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12.5, color: t.textFaint, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter({
    required this.progress,
    required this.t,
    required this.color,
    required this.track,
    required this.indeterminate,
  });

  final double progress;
  final double t;
  final Color color;
  final Color track;
  final bool indeterminate;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 14;
    const start = -math.pi / 2;

    // Outward pulses; they get more energetic as the conversion advances.
    final energy = 0.35 + progress * 0.65;
    for (var i = 0; i < 3; i++) {
      final phase = (t + i / 3) % 1.0;
      final fade = (1 - phase) * 0.28 * energy;
      if (fade <= 0.01) continue;
      canvas.drawCircle(
        center,
        r + phase * 16,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = color.withValues(alpha: fade.clamp(0.0, 1.0)),
      );
    }

    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..color = track,
    );

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..color = color;

    if (indeterminate) {
      final sweep = math.pi * 0.6;
      canvas.drawArc(Rect.fromCircle(center: center, radius: r), start + t * math.pi * 2, sweep, false, arc);
      return;
    }

    if (progress > 0.001) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r),
        start,
        math.pi * 2 * progress,
        false,
        arc,
      );

      // A bright head on the leading edge of the arc.
      final angle = start + math.pi * 2 * progress;
      final head = Offset(center.dx + r * math.cos(angle), center.dy + r * math.sin(angle));
      final glow = 0.6 + 0.4 * math.sin(t * math.pi * 2);
      canvas.drawCircle(head, 6.5 + glow * 3, Paint()..color = color.withValues(alpha: 0.18));
      canvas.drawCircle(head, 5, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.progress != progress || old.t != t || old.color != color || old.indeterminate != indeterminate;
}
