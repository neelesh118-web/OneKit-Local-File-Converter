import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onekit_converter/core/share/share_intake.dart';
import 'package:xml/xml.dart';

/// Two things sharing depends on that can be checked without a device: the
/// payload Android sends is read defensively, and the manifest still declares
/// the intents and no storage permission.
///
/// The manifest test is a guard, not a formality. Share support is exactly the
/// kind of change that tempts someone to add `READ_EXTERNAL_STORAGE`, and the
/// store listing tells users this app has no storage access at all. The listing
/// was verified against the built APK; this is the check that runs on every
/// commit.
void main() {
  group('SharedFile payload parsing', () {
    test('reads the paths and names the platform hands over', () {
      final files = SharedFile.listFromChannel([
        {'path': '/data/cache/inbox/holiday.jpg', 'name': 'holiday.jpg'},
        {'path': '/data/cache/inbox/report.pdf', 'name': 'report.pdf'},
      ]);

      expect(files, hasLength(2));
      expect(files.first.path, endsWith('holiday.jpg'));
      expect(files.first.name, 'holiday.jpg');
      expect(files.last.name, 'report.pdf');
    });

    test('falls back to the file name when the platform sent none', () {
      final files = SharedFile.listFromChannel([
        {'path': '/data/cache/inbox/clip.mp4'},
        {'path': 'C:/tmp/thing.png', 'name': ''},
      ]);

      expect(files.first.name, 'clip.mp4');
      expect(files.last.name, endsWith('thing.png'));
    });

    test('drops malformed entries instead of throwing', () {
      final files = SharedFile.listFromChannel([
        {'path': ''},
        {'name': 'no-path.mp4'},
        'not a map',
        42,
        null,
        {'path': '/ok/keep.png', 'name': 'keep.png'},
      ]);

      expect(files, hasLength(1));
      expect(files.single.name, 'keep.png');
    });

    test('an empty or unexpected payload is simply nothing', () {
      expect(SharedFile.listFromChannel(null), isEmpty);
      expect(SharedFile.listFromChannel('nonsense'), isEmpty);
      expect(SharedFile.listFromChannel(<Object?>[]), isEmpty);
    });
  });

  group('AndroidManifest share declarations', () {
    late XmlElement activity;

    String? attr(XmlElement element, String name) {
      for (final attribute in element.attributes) {
        final local = attribute.name.local.split(':').last;
        if (local == name) return attribute.value;
      }
      return null;
    }

    String localName(XmlElement element) => element.name.local.split(':').last;

    setUpAll(() {
      final manifest = XmlDocument.parse(
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
      );

      final activities = manifest
          .findAllElements('activity')
          .where((e) => localName(e) == 'activity')
          .toList();
      activity = activities.firstWhere(
        (e) => (attr(e, 'name') ?? '').endsWith('MainActivity'),
        orElse: () => throw StateError('MainActivity is not declared'),
      );
    });

    List<XmlElement> filters() => activity
        .childElements
        .where((e) => localName(e) == 'intent-filter')
        .toList();

    Set<String> actionsOf(XmlElement filter) => {
          for (final action in filter.childElements.where((e) => localName(e) == 'action'))
            attr(action, 'name') ?? '',
        };

    Set<String> mimeTypesOf(XmlElement filter) => {
          for (final data in filter.childElements.where((e) => localName(e) == 'data'))
            if (attr(data, 'mimeType') != null) attr(data, 'mimeType')!,
        };

    test('accepts files shared from any app, and several at once', () {
      final byAction = <String, XmlElement>{};
      for (final filter in filters()) {
        for (final action in actionsOf(filter)) {
          byAction[action] = filter;
        }
      }

      final send = byAction['android.intent.action.SEND'];
      final sendMultiple = byAction['android.intent.action.SEND_MULTIPLE'];
      expect(send, isNotNull, reason: 'SEND is what a share sheet uses');
      expect(sendMultiple, isNotNull, reason: 'SEND_MULTIPLE is a multi-file share');

      // A converter should accept anything it might recognise and explain
      // itself when it does not, rather than hiding from the share sheet.
      expect(mimeTypesOf(send!), contains('*/*'));
      expect(mimeTypesOf(sendMultiple!), contains('*/*'));
    });

    test('open-with is offered for what the app can actually convert', () {
      final view = filters().firstWhere(
        (f) => actionsOf(f).contains('android.intent.action.VIEW'),
      );
      final types = mimeTypesOf(view);

      expect(
        types,
        containsAll(<String>[
          'image/*',
          'audio/*',
          'video/*',
          'application/pdf',
        ]),
      );
      // Not everything: registering for */* would put OneKit in the Open with
      // list for formats it cannot read, which is a promise the conversion
      // matrix refuses to make anywhere else.
      expect(types, isNot(contains('*/*')));
    });

    test('the activity is the single instance a second share lands on', () {
      expect(attr(activity, 'launchMode'), 'singleTop');
      expect(attr(activity, 'exported'), 'true');
    });

    test('sharing adds no storage permission', () {
      final manifest = XmlDocument.parse(
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
      );
      final storageish = RegExp(
        r'STORAGE|READ_MEDIA|MANAGE_EXTERNAL|ACCESS_MEDIA_LOCATION',
      );

      for (final element in manifest.findAllElements('uses-permission')) {
        final name = attr(element, 'name') ?? '';
        if (!storageish.hasMatch(name)) continue;
        expect(
          attr(element, 'node'),
          'remove',
          reason: '$name must stay stripped, or the listing is no longer true',
        );
      }
    });

    test('the permissions the listing does declare are still there', () {
      final manifest = XmlDocument.parse(
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
      );
      final declared = {
        for (final element in manifest.findAllElements('uses-permission'))
          attr(element, 'name') ?? '',
      };

      expect(
        declared,
        containsAll(<String>[
          'android.permission.INTERNET',
          'android.permission.ACCESS_NETWORK_STATE',
          'android.permission.WAKE_LOCK',
          'com.google.android.gms.permission.AD_ID',
        ]),
      );
    });
  });
}
