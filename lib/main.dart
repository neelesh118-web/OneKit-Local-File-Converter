import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/ads/ads.dart';
import 'core/data/settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Draw behind the status and navigation bars; every screen then insets its
  // own content with SafeArea so nothing ever collides with system chrome.
  // Neither of these needs to gate the first frame, so the orientation lock
  // runs alongside the preference load rather than before it.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final results = await Future.wait([
    SettingsStore.load(),
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]),
  ]);
  final settings = results.first as SettingsStore;

  runApp(
    ChangeNotifierProvider<SettingsStore>.value(
      value: settings,
      child: const LocalFileConverterApp(),
    ),
  );

  // Give Flutter time to render the launch sequence and the first usable
  // screen before the ads SDK starts loading native code and WebView pieces.
  // This keeps monetisation from competing with the first frame.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(
      Future<void>.delayed(
        const Duration(milliseconds: 3500),
        AdManager.instance.initialize,
      ),
    );
  });
}
