import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/data/settings_store.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/starfield.dart';

/// Three-screen onboarding shown on first launch. Teaches the core flow
/// without overwhelming the user.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _controller = PageController();
  int _page = 0;

  static const _pages = [
    _OnboardData(
      icon: Icons.touch_app_rounded,
      title: 'Pick a file',
      body: 'Select anything on your device.\nThis app works out what it can become.',
    ),
    _OnboardData(
      icon: Icons.autorenew_rounded,
      title: 'Convert instantly',
      body: '5,000+ conversions across images,\naudio, video, documents and more.',
    ),
    _OnboardData(
      icon: Icons.lock_outline_rounded,
      title: '100% private',
      body: 'Everything runs on your device.\nNo uploads, no internet needed.',
    ),
  ];

  void _next() {
    if (_page < _pages.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      _finish();
    }
  }

  void _finish() {
    context.read<SettingsStore>().setOnboarded(true);
    context.go('/');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final isLast = _page == _pages.length - 1;

    return Scaffold(
      backgroundColor: t.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Starfield(density: 0.8, speed: 0.6),
          SafeArea(
            child: Column(
              children: [
                // Skip button
                Align(
                  alignment: Alignment.topRight,
                  child: TextButton(
                    onPressed: _finish,
                    child: Text(
                      'Skip',
                      style: TextStyle(color: t.textFaint, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                // Page view
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _pages.length,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (_, i) {
                      final d = _pages[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 100,
                              height: 100,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: t.border, width: 2),
                              ),
                              child: Icon(d.icon, size: 48, color: t.textPrimary),
                            ),
                            const SizedBox(height: 36),
                            Text(
                              d.title,
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: t.textPrimary,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              d.body,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 15,
                                height: 1.5,
                                color: t.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                // Dots + button
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    24, 0, 24, MediaQuery.viewPaddingOf(context).bottom + 24,
                  ),
                  child: Column(
                    children: [
                      // Page indicators
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < _pages.length; i++)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              width: i == _page ? 24 : 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: i == _page ? t.accent : t.border,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: FilledButton(
                          onPressed: _next,
                          child: Text(isLast ? "Let's go" : 'Next'),
                        ),
                      ),
                    ],
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

class _OnboardData {
  const _OnboardData({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;
}
