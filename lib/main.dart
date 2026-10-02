import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/ads/ads.dart';
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

  // Ads start on the first frame rather than in front of it: nothing about the
  // first paint should wait on a consent round trip, and the form the consent
  // SDK may put up must not land on a splash screen that has not drawn yet.
  //
  // The one launch that stays clean is the first one, before onboarding is
  // done: an ad in front of a new user buys a single impression with the whole
  // first opinion of the app.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(
      () async {
        await AdManager.instance.start(firstRunComplete: settings.onboarded);
        await AdManager.instance.showAppOpenOnLaunch();
      }(),
    );
  });
}
