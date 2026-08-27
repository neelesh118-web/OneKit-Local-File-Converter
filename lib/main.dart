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
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final settings = await SettingsStore.load();

  runApp(
    ChangeNotifierProvider<SettingsStore>.value(
      value: settings,
      child: const OneKitApp(),
    ),
  );

  // Ads initialise after the first frame is scheduled so nothing about the
  // SDK's start-up can delay the splash.
  unawaited(AdManager.instance.initialize());
}
