import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:onekit_converter/core/theme/app_theme.dart';

/// The launcher icon, drawn rather than shipped as a bitmap.
///
/// It is the app's own mark — the numeral one with two chevrons converging on
/// it, one file going in and one coming out — on the same black-and-stars
/// background the app paints behind its screens. Drawing it here rather than
/// exporting a PNG from a design tool means the icon is one command away from
/// being changed, and that every size down to 48px is rendered from the real
/// shapes instead of resampled from one big one.
///
/// The three Android layers an adaptive icon needs come out of the same
/// painter: a full tile for older launchers, a background, and a foreground
/// that keeps its artwork inside the central 66% the platform reserves.
class OneKitIconPainter extends CustomPainter {
  const OneKitIconPainter({
    this.tile = true,
    this.glyph = true,
    this.glyphScale = 0.67,
    this.flat = false,
  });

  /// Paints the starfield and its dome of light. Off for the foreground and
  /// monochrome layers, which arrive on transparency.
  final bool tile;

  /// Paints the mark. Off for the background layer alone.
  final bool glyph;

  /// The mark's width as a fraction of the tile.
  final double glyphScale;

  /// Drops the glow and the gradient, leaving a flat white silhouette — which
  /// is what a themed icon has to be, because the launcher recolours it.
  final bool flat;

  /// The same seed every time: a background that shimmered differently on each
  /// run would put a new icon in the repository for no reason.
  static const _seed = 20261002;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final rect = Rect.fromLTWH(0, 0, s, s);
    if (tile) _paintBackground(canvas, rect, s);
    if (glyph) _paintMark(canvas, s);
  }

  void _paintBackground(Canvas canvas, Rect rect, double s) {
    // A dome of light rather than a flat fill: on a home screen full of flat
    // squares, depth is what makes an icon look deliberate.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -0.30),
          radius: 1.05,
          colors: [Color(0xFF262B38), Color(0xFF0C0E14), Mono.black],
          stops: [0.0, 0.50, 1.0],
        ).createShader(rect),
    );

    final rng = math.Random(_seed);

    // The dust: faint enough that the brighter stars below are what the eye
    // finds first. At 48px this is texture rather than points of light, which
    // is the point — a launcher tile should not look like a photograph.
    for (var i = 0; i < 66; i++) {
      final centre = Offset(rng.nextDouble() * s, rng.nextDouble() * s);
      final radius = s * (0.0016 + rng.nextDouble() * 0.0034);
      final alpha = 0.14 + rng.nextDouble() * 0.34;
      canvas.drawCircle(centre, radius, Paint()..color = Mono.white.withValues(alpha: alpha));
    }

    // Seven brighter stars, each with the smallest halo that still suggests it
    // is shining rather than painted on.
    for (var i = 0; i < 7; i++) {
      final centre = Offset(rng.nextDouble() * s, rng.nextDouble() * s);
      final radius = s * (0.0038 + rng.nextDouble() * 0.0022);
      canvas.drawCircle(
        centre,
        radius * 3.6,
        Paint()
          ..color = Mono.white.withValues(alpha: 0.14)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.013),
      );
      canvas.drawCircle(centre, radius, Paint()..color = Mono.white.withValues(alpha: 0.92));
    }
  }

  void _paintMark(Canvas canvas, double s) {
    final box = s * glyphScale;
    final origin = (s - box) / 2;
    Offset at(double x, double y) => Offset(origin + x * box, origin + y * box);

    // The numeral one: flag, then stem. Heavier than the in-app mark, which is
    // read at arm's length rather than across a room.
    final start = at(0.392, 0.392);
    final shoulder = at(0.500, 0.305);
    final foot = at(0.500, 0.715);
    final stem = Path()
      ..moveTo(start.dx, start.dy)
      ..lineTo(shoulder.dx, shoulder.dy)
      ..moveTo(shoulder.dx, shoulder.dy)
      ..lineTo(foot.dx, foot.dy);
    final stemWidth = box * 0.120;

    // Two chevrons pointing in at the numeral: in on the left, out on the
    // right, which is the whole idea of the app in one glyph.
    final inLeft = at(0.196, 0.398);
    final inMid = at(0.296, 0.500);
    final inLow = at(0.196, 0.602);
    final outHigh = at(0.804, 0.398);
    final outMid = at(0.704, 0.500);
    final outLow = at(0.804, 0.602);
    final chevrons = Path()
      ..moveTo(inLeft.dx, inLeft.dy)
      ..lineTo(inMid.dx, inMid.dy)
      ..lineTo(inLow.dx, inLow.dy)
      ..moveTo(outHigh.dx, outHigh.dy)
      ..lineTo(outMid.dx, outMid.dy)
      ..lineTo(outLow.dx, outLow.dy);
    final chevronWidth = box * 0.086;

    Paint stroke(double width) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = width;

    if (!flat) {
      // The halo first, so the crisp strokes land on top of it. Without it the
      // mark reads as a sticker laid on the background rather than part of it.
      final halo = stroke(0)
        ..color = Mono.white.withValues(alpha: 0.30)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.030);
      canvas.drawPath(stem, halo..strokeWidth = stemWidth * 1.5);
      canvas.drawPath(chevrons, halo..strokeWidth = chevronWidth * 1.6);
    }

    final mark = stroke(0);
    if (flat) {
      mark.color = Mono.white;
    } else {
      // A whisper of a gradient down the mark: enough to catch the light on a
      // dark home screen, not enough to look like a bevel.
      mark.shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Mono.white, Color(0xFFDCDCE4)],
      ).createShader(Rect.fromCircle(center: at(0.5, 0.5), radius: box * 0.6));
    }

    canvas.drawPath(stem, mark..strokeWidth = stemWidth);
    canvas.drawPath(chevrons, mark..strokeWidth = chevronWidth);
  }

  @override
  bool shouldRepaint(OneKitIconPainter old) =>
      old.tile != tile || old.glyph != glyph || old.glyphScale != glyphScale || old.flat != flat;
}
