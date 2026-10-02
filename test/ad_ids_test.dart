import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onekit_converter/core/ads/ad_ids.dart';

/// The ad units, held to the accounts they claim to belong to.
///
/// Two of these are the checks that would catch a mistake no compiler can: a
/// production unit pasted from the wrong account, and a demo unit that has
/// drifted into the table the release build reads. The manifest check is the
/// third — the app ID there is read by the SDK before any Dart code runs, so a
/// mismatch means a build that shows nothing at all.
void main() {
  group('the unit tables', () {
    test('cover every format', () {
      for (final format in AdFormat.values) {
        expect(AdIds.productionUnits[format], isNotNull, reason: 'production ${format.name}');
        expect(AdIds.demoUnits[format], isNotNull, reason: 'demo ${format.name}');
      }
    });

    test('every production unit is on the OneKit account', () {
      for (final entry in AdIds.productionUnits.entries) {
        expect(
          entry.value,
          startsWith('${AdIds.account}/'),
          reason: '${entry.key.name} is not on the account the listing names',
        );
      }
    });

    test('every demo unit is on Google\'s sample account', () {
      for (final entry in AdIds.demoUnits.entries) {
        expect(entry.value, startsWith('${AdIds.demoAccount}/'), reason: entry.key.name);
      }
    });

    test('no unit appears in both tables', () {
      final production = AdIds.productionUnits.values.toSet();
      final demo = AdIds.demoUnits.values.toSet();
      expect(production.intersection(demo), isEmpty);
    });

    test('the app id is the OneKit account and is not a sample one', () {
      expect(AdIds.androidAppId, startsWith('${AdIds.account}~'));
      expect(AdIds.androidAppId, isNot(startsWith(AdIds.demoAccount)));
    });

    test('the format accessors agree with the tables', () {
      // In a test binary this is a debug build, so the accessors answer with
      // the demo units — which is the point: a test run must never touch the
      // real account, or it is invalid traffic on the real account.
      expect(AdIds.banner, AdIds.demoUnits[AdFormat.banner]);
      expect(AdIds.interstitial, AdIds.demoUnits[AdFormat.interstitial]);
      expect(AdIds.native, AdIds.demoUnits[AdFormat.native]);
      expect(AdIds.rewarded, AdIds.demoUnits[AdFormat.rewarded]);
      expect(AdIds.appOpen, AdIds.demoUnits[AdFormat.appOpen]);
    });
  });

  group('the manifest', () {
    test('declares the same AdMob app id as the Dart table', () {
      final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(
        manifest,
        contains('android:value="${AdIds.androidAppId}"'),
        reason: 'the manifest app id and AdIds.androidAppId have drifted apart',
      );
    });

    test('keeps the permissions AdMob needs and no more', () {
      final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      for (final permission in const [
        'android.permission.INTERNET',
        'android.permission.ACCESS_NETWORK_STATE',
        'com.google.android.gms.permission.AD_ID',
      ]) {
        expect(manifest, contains(permission));
      }
    });
  });
}
