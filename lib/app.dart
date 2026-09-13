import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/data/settings_store.dart';
import 'core/theme/app_theme.dart';
import 'features/about/about_page.dart';
import 'features/batch/batch_page.dart';
import 'features/convert/convert_page.dart';
import 'features/files/files_page.dart';
import 'features/history/history_page.dart';
import 'features/home/home_page.dart';
import 'features/home/onboarding_page.dart';
import 'features/home/pairs_page.dart';
import 'features/home/splash_page.dart';
import 'features/settings/settings_page.dart';
import 'shell.dart';

class LocalFileConverterApp extends StatelessWidget {
  const LocalFileConverterApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsStore>();
    return MaterialApp.router(
      title: '100% Local File Converter',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: _router,
      builder: (context, child) {
        // Clamp text scaling so the dense format grids stay readable without
        // ignoring the user's accessibility preference entirely.
        final scale = MediaQuery.textScalerOf(context).clamp(minScaleFactor: 0.85, maxScaleFactor: 1.35);
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: scale),
          child: child!,
        );
      },
    );
  }
}

final _shellKey = GlobalKey<NavigatorState>();

final GoRouter _router = GoRouter(
  initialLocation: '/splash',
  routes: [
    GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingPage()),
    GoRoute(path: '/splash', builder: (_, __) => const SplashPage()),
    GoRoute(
      path: '/convert',
      builder: (_, state) => ConvertPage(args: state.extra as ConvertArgs?),
    ),
    GoRoute(path: '/pairs', builder: (_, state) => PairsPage(initialQuery: state.uri.queryParameters['q'])),
    GoRoute(path: '/about', builder: (_, __) => const AboutPage()),
    ShellRoute(
      navigatorKey: _shellKey,
      builder: (context, state, child) => AppShell(location: state.uri.path, child: child),
      routes: [
        GoRoute(path: '/', pageBuilder: (_, s) => _fade(s, const HomePage())),
        GoRoute(path: '/batch', pageBuilder: (_, s) => _fade(s, const BatchPage())),
        GoRoute(path: '/history', pageBuilder: (_, s) => _fade(s, const HistoryPage())),
        GoRoute(path: '/files', pageBuilder: (_, s) => _fade(s, const FilesPage())),
        GoRoute(path: '/settings', pageBuilder: (_, s) => _fade(s, const SettingsPage())),
      ],
    ),
  ],
);

/// Tab switches cross-fade instead of sliding; a slide would fight the
/// starfield, which is painted once behind the whole shell.
CustomTransitionPage<void> _fade(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 160),
    transitionsBuilder: (context, animation, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: child,
    ),
  );
}
