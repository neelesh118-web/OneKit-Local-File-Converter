import 'dart:io';

import 'package:archive/archive_io.dart';

/// What a release bundle has to prove before it is uploaded.
///
/// Every check here is a read-back rather than an assumption, because each of
/// these has been wrong at least once in this project's short history: a
/// `versionCode` Play had already used, an ad unit that never loaded because
/// nothing called the initialiser, a consent switch that would have shipped in
/// a release build. The bundle is a zip and the interesting parts are plain
/// entries inside it, so this opens it and looks.
///
/// ```
/// dart run tool/release_check.dart build/app/outputs/bundle/release/app-release.aab
/// dart run tool/release_check.dart build/app/outputs/flutter-apk/app-release.apk
/// ```
///
/// Exit code 1 means the bundle contradicts the app's own claims and should not
/// be uploaded. Exit code 2 means the tool could not read the artifact at all.
void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/release_check.dart <bundle.aab|app.apk>');
    exit(2);
  }

  final file = File(args.first);
  if (!file.existsSync()) {
    stderr.writeln('no such artifact: ${file.path}');
    exit(2);
  }

  stdout.writeln('${file.path}  (${file.lengthSync()} bytes)');

  final isBundle = file.path.endsWith('.aab');
  final archive = ZipDecoder().decodeStream(InputFileStream(file.path));
  final names = [for (final f in archive.files) f.name];

  var failures = 0;
  var checks = 0;
  void check(String what, bool ok, [String? detail]) {
    checks++;
    if (ok) {
      stdout.writeln('  ok    $what');
      return;
    }
    failures++;
    stdout.writeln('  FAIL  $what${detail == null ? '' : ' — $detail'}');
  }

  /// Decompresses one entry by name, or null when it is not in the bundle.
  String? entryText(String name, {bool dense = false}) {
    final entry = archive.findFile(name);
    if (entry == null) return null;
    final bytes = entry.readBytes() ?? const <int>[];
    return dense ? _readableDense(bytes) : _readable(bytes);
  }

  // ---- the version, which Play keys on ---------------------------------
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final version = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec)!.group(1)!;
  final expectedCode = version.split('+').last;
  final expectedName = version.split('+').first;

  // The AAB's manifest is protobuf; the APK's is Android's binary XML, where
  // the strings live in a pool with a length in front of each one. Both are
  // read as text: the protobuf with its padding kept as separators, the binary
  // XML with the padding dropped so a UTF-16 string rejoins itself.
  final manifestName = isBundle
      ? names.firstWhere((n) => n.endsWith('AndroidManifest.xml'), orElse: () => '')
      : 'AndroidManifest.xml';
  final manifest = entryText(manifestName);
  final denseManifest = entryText(manifestName, dense: true);
  check('the bundle has a manifest', manifest != null, manifestName);

  if (manifest != null && denseManifest != null) {
    final code = RegExp(r'versionCode[^0-9]{0,8}(\d+)').firstMatch(manifest)?.group(1);
    final name = RegExp(r'versionName[^0-9A-Za-z.]{0,8}([0-9][0-9A-Za-z.]*)').firstMatch(manifest)?.group(1);
    if (isBundle) {
      check('versionCode is $expectedCode (found $code)', code == expectedCode);
      check('versionName is $expectedName (found $name)', name == expectedName);
    } else {
      // Binary XML keeps versionCode as a machine integer, so the name is what
      // can be read out of the bytes; aapt2 is asked for both when it is here.
      final badging = _aaptBadging(file);
      if (badging != null) {
        check(
          'versionCode is $expectedCode (aapt2 says ${badging['versionCode']})',
          badging['versionCode'] == expectedCode,
        );
        check(
          'versionName is $expectedName (aapt2 says ${badging['versionName']})',
          badging['versionName'] == expectedName,
        );
      } else {
        stdout.writeln('  skip  versionCode/versionName: aapt2 not found to read binary XML');
        check('versionName $expectedName is in the manifest', denseManifest.contains(expectedName));
      }
    }
    check(
      'the AdMob app id is the OneKit account',
      denseManifest.contains('ca-app-pub-2489505475567649'),
      'the SDK reads this before any Dart code runs',
    );
  }

  // ---- the Dart code, as it was actually compiled ----------------------
  // The AOT snapshot holds the app's own strings, which is where the ad units
  // and the consent switches live. Nothing third-party is in here, so a demo
  // unit found below is the app's own and not a plugin's.
  final snapshots = [
    for (final name in names)
      if (name.endsWith('libapp.so')) name,
  ];
  check('the app code is in the bundle', snapshots.isNotEmpty, snapshots.join(', '));

  final appCode = StringBuffer();
  for (final name in snapshots) {
    appCode.write(entryText(name) ?? '');
  }
  final code = appCode.toString();

  check(
    'the banner unit is present',
    code.contains('ca-app-pub-2489505475567649/7225824219'),
    'the release ad layer is not in this build',
  );
  check('the interstitial unit is present', code.contains('ca-app-pub-2489505475567649/5936793275'));
  check('the native unit is present', code.contains('ca-app-pub-2489505475567649/1095530132'));
  check('the rewarded unit is present', code.contains('ca-app-pub-2489505475567649/6329394147'));
  // Build 5 swapped this unit: the first one never served (see
  // store/releases.md, build 4 — "Ad unit doesn't match format").
  check('the app-open unit is present', code.contains('ca-app-pub-2489505475567649/9898941203'));

  check(
    'no demo ad units in the app code',
    !code.contains('ca-app-pub-3940256099942544'),
    'a sample unit would ship to the real account as invalid traffic',
  );
  check(
    'no consent debug switches in the app code',
    !code.contains('ONEKIT_CONSENT_GEOGRAPHY') &&
        !code.contains('ONEKIT_CONSENT_TEST_IDS') &&
        !code.contains('ONEKIT_CONSENT_RESET'),
    'the debug geography and reset switches must fold away in a release build',
  );

  // ---- and that it is signed at all ------------------------------------
  // The AAB is a jar signature, so the certificate is an entry. An APK is
  // normally signed with the APK Signature Scheme instead, where the signature
  // is a block of bytes after the zip entries and before the central directory,
  // marked with a magic string that is the only visible sign of it.
  final jarSigned = names.any((n) => n.startsWith('META-INF/') && n.endsWith('.RSA'));
  final apkSigned = isBundle ? false : _hasApkSignatureBlock(file);
  check(
    'the artifact carries a signature',
    jarSigned || apkSigned,
    jarSigned ? null : 'neither a jar certificate nor an APK signing block was found',
  );

  stdout.writeln('\n$checks checks, $failures failing');
  if (failures > 0) {
    stdout.writeln('This bundle is not the one to upload.');
    exit(1);
  }
  stdout.writeln('The bundle agrees with the tree it came from.');
}

/// Keeps the printable strings and drops the padding.
///
/// Protobuf and the AOT snapshot both store their strings with lengths and
/// alignment around them; the text survives as a run of printable bytes with
/// nulls in between, so this keeps what is readable and turns the rest into a
/// separator that cannot bridge two strings.
String _readable(List<int> bytes) {
  final out = StringBuffer();
  for (final byte in bytes) {
    if (byte >= 32 && byte < 127) {
      out.writeCharCode(byte);
    } else {
      out.write('\u0000');
    }
  }
  return out.toString();
}

/// The same, with the padding removed entirely.
///
/// Android's binary XML stores most strings as UTF-16, so an ASCII string
/// arrives as letter, null, letter, null. Dropping the nulls puts it back
/// together, which is what makes the app id and the version name findable in
/// an APK's manifest without a binary-XML parser.
String _readableDense(List<int> bytes) {
  final out = StringBuffer();
  for (final byte in bytes) {
    if (byte >= 32 && byte < 127) out.writeCharCode(byte);
  }
  return out.toString();
}

/// Whether an APK carries an APK Signature Scheme block.
///
/// The block sits immediately before the central directory and ends with the
/// magic "APK Sig Block 42", so a plain substring search over the last few
/// kilobytes is enough to tell a signed APK from an unsigned one.
bool _hasApkSignatureBlock(File file) {
  const magic = 'APK Sig Block 42';
  final length = file.lengthSync();
  final tailLength = length < 200000 ? length : 200000;
  final tail = file.openSync()
    ..setPositionSync(length - tailLength);
  final bytes = tail.readSync(tailLength);
  tail.closeSync();
  return _readableDense(bytes).contains(magic);
}

/// Asks the Android SDK's aapt2 for an APK's badging, when it is installed.
///
/// Binary XML is not worth writing a parser for when the platform's own tool
/// is one `where` away, and its answer is the one Play itself reads.
Map<String, String?>? _aaptBadging(File apk) {
  final sdk = Platform.environment['ANDROID_HOME'] ??
      Platform.environment['ANDROID_SDK_ROOT'] ??
      '${Platform.environment['LOCALAPPDATA']}\\Android\\Sdk';
  final buildTools = Directory('$sdk\\build-tools');
  if (!buildTools.existsSync()) return null;

  final versions = buildTools.listSync().whereType<Directory>().toList()
    ..sort((a, b) => b.path.compareTo(a.path));
  for (final version in versions) {
    final aapt2 = File('${version.path}\\aapt2.exe');
    if (!aapt2.existsSync()) continue;
    final result = Process.runSync(aapt2.path, ['dump', 'badging', apk.path]);
    if (result.exitCode != 0) continue;
    final text = result.stdout.toString();
    return {
      'versionCode': RegExp(r"versionCode='([^']*)'").firstMatch(text)?.group(1),
      'versionName': RegExp(r"versionName='([^']*)'").firstMatch(text)?.group(1),
    };
  }
  return null;
}
