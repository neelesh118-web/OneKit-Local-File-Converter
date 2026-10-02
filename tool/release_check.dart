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
  String? entryText(String name) {
    final entry = archive.findFile(name);
    if (entry == null) return null;
    return _readable(entry.readBytes() ?? const <int>[]);
  }

  // ---- the version, which Play keys on ---------------------------------
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final version = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec)!.group(1)!;
  final expectedCode = version.split('+').last;
  final expectedName = version.split('+').first;

  // The AAB's manifest is protobuf and the APK's is binary XML; both keep their
  // strings readable once the padding is dropped.
  final manifestName = isBundle
      ? names.firstWhere((n) => n.endsWith('AndroidManifest.xml'), orElse: () => '')
      : 'AndroidManifest.xml';
  final manifest = entryText(manifestName);
  check('the bundle has a manifest', manifest != null, manifestName);
  if (manifest != null) {
    final code = RegExp(r'versionCode[^0-9]{0,8}(\d+)').firstMatch(manifest)?.group(1);
    final name = RegExp(r'versionName[^0-9A-Za-z.]{0,8}([0-9][0-9A-Za-z.]*)').firstMatch(manifest)?.group(1);
    check('versionCode is $expectedCode (found $code)', code == expectedCode);
    check('versionName is $expectedName (found $name)', name == expectedName);
    check(
      'the AdMob app id is the OneKit account',
      manifest.contains('ca-app-pub-2489505475567649'),
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
  check('the app-open unit is present', code.contains('ca-app-pub-2489505475567649/9684466592'));

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
  final signed = isBundle
      ? names.any((n) => n.startsWith('META-INF/') && n.endsWith('.RSA'))
      : names.any((n) => n.startsWith('META-INF/') && n.endsWith('.RSA'));
  check('the artifact carries a signature', signed, names.where((n) => n.startsWith('META-INF/')).join(', '));

  stdout.writeln('\n$checks checks, $failures failing');
  if (failures > 0) {
    stdout.writeln('This bundle is not the one to upload.');
    exit(1);
  }
  stdout.writeln('The bundle agrees with the tree it came from.');
}

/// Keeps the printable strings and drops the padding.
///
/// Protobuf and Android's binary XML both store their strings as UTF-8 or
/// UTF-16 with lengths and alignment around them; the AOT snapshot stores them
/// in a string table. In all three cases the text survives as a run of
/// printable bytes with nulls in between, so this keeps what is readable and
/// turns the rest into a separator that cannot bridge two strings.
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
