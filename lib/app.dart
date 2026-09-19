import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/data/settings_store.dart';
import 'core/share/share_intake.dart';
import 'core/theme/app_theme.dart';
import 'features/about/about_page.dart';
import 'features/batch/batch_page.dart';
import 'features/convert/convert_page.dart';
import 'features/feedback/feedback_page.dart';
import 'features/files/files_page.dart';
import 'features/history/history_page.dart';
import 'features/home/home_page.dart';
import 'features/home/onboarding_page.dart';
import 'features/home/pairs_page.dart';
import 'features/home/splash_page.dart';
import 'features/pdf_tools/pdf_tools_page.dart';
import 'features/presets/presets_page.dart';
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
          // Sits above the router so a file shared in from another app can be
          // routed without any screen having to know about sharing.
          child: ShareGate(router: _router, child: child!),
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
    GoRoute(path: '/presets', builder: (_, __) => const PresetsPage()),
    GoRoute(
      path: '/feedback',
      builder: (_, state) => FeedbackPage(args: state.extra as FeedbackArgs?),
    ),
    GoRoute(
      path: '/pdf-tools',
      builder: (_, state) =>
          PdfToolsPage(initialPaths: (state.extra as List<String>?) ?? const []),
    ),
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

/// Hands files other apps share into OneKit to the screen that wants them.
///
/// A share that launched the app has to wait its turn: the splash navigates to
/// Home — or to onboarding on a first run — when it is done, and that navigation
/// would wipe out anything pushed before it. So a share is held until the router
/// has left both. Nothing here decides anything about the file itself; the
/// conversion screen and the batch queue already know what to do with a path.
class ShareGate extends StatefulWidget {
  const ShareGate({super.key, required this.router, required this.child});

  final GoRouter router;
  final Widget child;

  @override
  State<ShareGate> createState() => _ShareGateState();
}

class _ShareGateState extends State<ShareGate> {
  StreamSubscription<List<SharedFile>>? _subscription;

  /// Files waiting for a screen that can show them.
  List<SharedFile>? _pending;

  @override
  void initState() {
    super.initState();
    // Listen before asking for the launch share. The platform flushes whatever
    // is waiting to whichever consumer appears first, and this order closes the
    // gap between the two — a share arriving in that gap would otherwise sit in
    // the queue until the next one.
    _subscription = ShareIntake.instance.incoming.listen(_offer);
    ShareIntake.instance.takeInitial().then(_offer);
    widget.router.routerDelegate.addListener(_deliver);
  }

  @override
  void dispose() {
    widget.router.routerDelegate.removeListener(_deliver);
    _subscription?.cancel();
    super.dispose();
  }

  /// Takes a handover from either consumer.
  ///
  /// The launch share can legitimately arrive twice — once as the reply to
  /// `takeInitial`, once as an event, because the platform hands it to whichever
  /// consumer is ready first and both are wired up at startup. An empty list is
  /// therefore treated as "nothing to report" rather than "the user shared
  /// something with no file in it": believing the second reading would let a
  /// later empty reply wipe out a share that is still waiting to be shown.
  void _offer(List<SharedFile> files) {
    if (files.isEmpty) return;
    _pending = files;
    _deliver();
  }

  /// Acts on a pending share once the router is somewhere it can act from.
  void _deliver() {
    final pending = _pending;
    if (pending == null || !mounted) return;

    final route = widget.router.routerDelegate.currentConfiguration.uri.path;
    if (route == '/splash' || route == '/onboarding') return;
    _pending = null;

    // Navigating from inside a router notification would be a build-time change
    // to the very route being built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (pending.length == 1) {
        final file = pending.first;
        widget.router.push(
          '/convert',
          extra: ConvertArgs(paths: [file.path], displayNames: [file.name]),
        );
        return;
      }
      // Several files at once is the batch flow: one target, one queue.
      BatchPage.seed([for (final file in pending) file.path]);
      widget.router.go('/batch');
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

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
