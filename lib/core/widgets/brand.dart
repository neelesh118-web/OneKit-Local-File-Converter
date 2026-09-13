import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The OneKit mark: a rounded square holding a "1" whose counter is cut by two
/// converging chevrons — one file going in, one coming out. Drawn rather than
/// shipped as a bitmap so it stays crisp at every size and inverts with theme.
class AppMark extends StatelessWidget {
  const AppMark({super.key, this.size = 72, this.inverted = false});

  final double size;

  /// Draws light-on-dark regardless of theme (used on the splash).
  final bool inverted;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final fg = inverted ? t.background : t.onAccent;
    final bg = inverted ? t.accent : t.accent;
    return CustomPaint(
      size: Size.square(size),
      painter: _MarkPainter(fg: fg, bg: bg),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter({required this.fg, required this.bg});
  final Color fg;
  final Color bg;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final rect = Rect.fromLTWH(0, 0, s, s);

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(s * 0.235)),
      Paint()..color = bg,
    );

    final stroke = Paint()
      ..color = fg
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.082
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // The numeral one: flag + stem.
    final stemX = s * 0.5;
    canvas.drawLine(Offset(stemX, s * 0.28), Offset(stemX, s * 0.74), stroke);
    canvas.drawLine(Offset(s * 0.38, s * 0.365), Offset(stemX, s * 0.275), stroke);

    // Converging chevrons: input on the left, output on the right.
    final chevron = Paint()
      ..color = fg
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.062
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final left = Path()
      ..moveTo(s * 0.235, s * 0.40)
      ..lineTo(s * 0.325, s * 0.51)
      ..lineTo(s * 0.235, s * 0.62);
    canvas.drawPath(left, chevron);

    final right = Path()
      ..moveTo(s * 0.765, s * 0.40)
      ..lineTo(s * 0.675, s * 0.51)
      ..lineTo(s * 0.765, s * 0.62);
    canvas.drawPath(right, chevron);
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.fg != fg || old.bg != bg;
}

/// Wordmark + mark lockup used on the splash and the about page.
class AppLockup extends StatelessWidget {
  const AppLockup({super.key, this.markSize = 88, this.showTagline = true});

  final double markSize;
  final bool showTagline;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppMark(size: markSize),
        SizedBox(height: markSize * 0.28),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '100%',
                style: TextStyle(fontWeight: FontWeight.w800, color: t.textPrimary),
              ),
            ],
          ),
          style: TextStyle(fontSize: markSize * 0.38, letterSpacing: -1.2, height: 1.0),
        ),
        if (showTagline) ...[
          SizedBox(height: markSize * 0.1),
          Text(
            'Local File Converter',
            style: TextStyle(
              fontSize: markSize * 0.115,
              letterSpacing: markSize * 0.045,
              fontWeight: FontWeight.w600,
              color: t.textFaint,
            ),
          ),
        ],
      ],
    );
  }
}

/// Small monochrome badge showing a file extension, used throughout the lists.
class FormatBadge extends StatelessWidget {
  const FormatBadge(this.text, {super.key, this.size = 42, this.filled = false});

  final String text;
  final double size;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final label = text.toUpperCase();
    // Long extensions shrink rather than overflow the badge.
    final fontSize = switch (label.length) {
      <= 3 => size * 0.30,
      4 => size * 0.25,
      5 => size * 0.21,
      _ => size * 0.175,
    };
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled ? t.accent : t.surfaceRaised,
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: filled ? t.accent : t.border),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
          color: filled ? t.onAccent : t.textPrimary,
        ),
      ),
    );
  }
}

/// Rotating conversion arrow used between two [FormatBadge]s.
class ConvertArrow extends StatelessWidget {
  const ConvertArrow({super.key, this.size = 20, this.angle = 0});
  final double size;
  final double angle;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle * math.pi / 180,
      child: Icon(Icons.arrow_forward_rounded, size: size, color: context.tokens.textFaint),
    );
  }
}
