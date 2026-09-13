import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/data/settings_store.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/pulse.dart';
import '../../core/widgets/starfield.dart';

/// Branding splash. The complete lockup settles early, then stays visible so
/// the native Android launch icon does not feel like it is being skipped.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    // Short enough that the phone does not feel stuck, but long enough
    // for the native launch icon to hand off smoothly.
    duration: const Duration(milliseconds: 2500),
  );
  late final AnimationController _breathe = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _go();
  }

  Future<void> _go() async {
    await _intro.forward().orCancel.catchError((_) {});
    if (!mounted) return;
    final onboarded = context.read<SettingsStore>().onboarded;
    context.go(onboarded ? '/' : '/onboarding');
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                final bottomPad = MediaQuery.viewPaddingOf(context).bottom;
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: IntrinsicHeight(
                      child: Column(
                        children: [
                          const Spacer(flex: 3),
                AnimatedBuilder(
                  animation: _breathe,
                  builder: (context, child) => Transform.scale(
                    scale: 1.0 + _breathe.value * 0.035,
                    child: child,
                  ),
                  child: const PulseHalo(
                    size: 190,
                    rings: 3,
                    child: AppMark(size: 96),
                  ),
                ),
                const SizedBox(height: 26),
                Column(
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '100%',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: t.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      style: const TextStyle(
                        fontSize: 42,
                        letterSpacing: -1.6,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Local File Converter',
                      style: TextStyle(
                        fontSize: 14,
                        letterSpacing: 2.0,
                        fontWeight: FontWeight.w500,
                        color: t.textFaint,
                      ),
                    ),
                  ],
                ),
                const Spacer(flex: 3),
                Padding(
                  padding: const EdgeInsets.only(bottom: 36),
                  child: Column(
                    children: [
                      const _Pill(
                        text: '5,000+ conversions',
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.lock_outline_rounded,
                            size: 13,
                            color: t.textFaint,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Runs entirely on your device',
                            style: TextStyle(
                              fontSize: 12,
                              color: t.textFaint,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

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
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: t.textSecondary,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
