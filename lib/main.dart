import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/data/preset_store.dart';
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
    PresetStore.load(),
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]),
  ]);
  final settings = results.first as SettingsStore;
  final presets = results[1] as PresetStore;

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsStore>.value(value: settings),
        // Saved recipes are read by Home, the convert screen and the batch
        // sheet, so they live above the router like the settings do.
        ChangeNotifierProvider<PresetStore>.value(value: presets),
      ],
      child: const LocalFileConverterApp(),
    ),
  );

  // TODO(screenshots): Re-enable ads after taking screenshots.
  // WidgetsBinding.instance.addPostFrameCallback((_) {
  //   unawaited(AdManager.instance.initialize());
  // });
}
