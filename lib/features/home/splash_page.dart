import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/pulse.dart';
import '../../core/widgets/starfield.dart';
import '../../engine/registry.dart';

/// Pulsating splash. The mark breathes inside an emanating halo while the
/// starfield falls behind it, then the whole lockup lifts away into the app.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  late final AnimationController _breathe = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat(reverse: true);

  late final Animation<double> _markIn = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.0, 0.55, curve: Curves.easeOutBack),
  );
  late final Animation<double> _textIn = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.35, 0.8, curve: Curves.easeOut),
  );
  late final Animation<double> _footIn = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.6, 1.0, curve: Curves.easeOut),
  );

  @override
  void initState() {
    super.initState();
    _go();
  }

  Future<void> _go() async {
    // Leave as soon as the intro has actually played, rather than sitting on a
    // fixed timer. The old unconditional 2.1s delay was ~700ms of dead time
    // after the animation had already settled, on every single launch.
    await _intro.forward().orCancel.catchError((_) {});
    if (mounted) context.go('/');
  }

  @override
  void dispose() {
    _intro.dispose();
    _breathe.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      backgroundColor: t.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Starfield(density: 1.35, speed: 1.6),
          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 3),
                ScaleTransition(
                  scale: Tween<double>(begin: 0.72, end: 1.0).animate(_markIn),
                  child: FadeTransition(
                    opacity: _markIn,
                    child: AnimatedBuilder(
                      animation: _breathe,
                      builder: (context, child) => Transform.scale(
                        scale: 1.0 + _breathe.value * 0.035,
                        child: child,
                      ),
                      child: const PulseHalo(
                        size: 190,
                        rings: 3,
                        child: OneKitMark(size: 96),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                FadeTransition(
                  opacity: _textIn,
                  child: SlideTransition(
                    position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(_textIn),
                    child: Column(
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: 'One', style: TextStyle(fontWeight: FontWeight.w800, color: t.textPrimary)),
                              TextSpan(text: 'Kit', style: TextStyle(fontWeight: FontWeight.w300, color: t.textPrimary)),
                            ],
                          ),
                          style: const TextStyle(fontSize: 42, letterSpacing: -1.6, height: 1.0),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'LOCAL FILE CONVERTER',
                          style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 4.2,
                            fontWeight: FontWeight.w600,
                            color: t.textFaint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(flex: 3),
                FadeTransition(
                  opacity: _footIn,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 36),
                    child: Column(
                      children: [
                        _Pill(text: '${_formatCount(FormatRegistry.pairCount)} conversions'),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.lock_outline_rounded, size: 13, color: t.textFaint),
                            const SizedBox(width: 6),
                            Text(
                              'Runs entirely on your device',
                              style: TextStyle(fontSize: 12, color: t.textFaint, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _formatCount(int n) => n >= 1000 ? '${(n / 1000).floor()},${(n % 1000).toString().padLeft(3, '0')}' : '$n';

class _Pill extends StatelessWidget {
  const _Pill({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: t.textSecondary, letterSpacing: 0.2),
      ),
    );
  }
}
