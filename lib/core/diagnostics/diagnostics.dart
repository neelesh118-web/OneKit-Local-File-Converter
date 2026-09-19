import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../engine/job.dart';
import '../data/history_store.dart';

/// The name a report calls the app. Deliberately the short form: this string
/// ends up in a subject line, where "100% Local File Converter" reads as noise.
const String productName = 'Local File Converter';

/// Where a report is meant to land. It is stated on the screen that sends one:
/// a tester handing over the details of their phone should know who reads them,
/// and the same address is already published in the privacy policy.
const String developerContact = 'neeleshasati118@gmail.com';

/// Facts about the device and the build, gathered for a failure report.
///
/// Two sources, because neither is enough on its own. Android knows what the
/// app cannot ask for on its own — the model, the OS release, where the build
/// was installed from — while Dart knows which mode the build was compiled in
/// and which engine it is running. The platform side is optional: on desktop,
/// and in a host test, the channel is simply absent and the report says so
/// instead of failing to be written. A report that cannot be produced is the
/// one thing this must never do, since the user has nothing else to send.
class EnvironmentInfo {
  EnvironmentInfo(this.fields);

  /// Display label to value, in the order the report prints them.
  final Map<String, String> fields;

  static const MethodChannel _channel = MethodChannel('onekit/diagnostics');

  /// What the report says about a fact this build cannot see.
  static const String unknown = 'unknown';

  /// Collects what can be collected. [extra] is for what only the calling
  /// screen knows — the screen size, the text scale — and it wins over a
  /// platform value with the same label.
  static Future<EnvironmentInfo> collect({
    Map<String, String> extra = const {},
  }) async {
    Map<String, dynamic> platform = const {};
    try {
      platform = await _channel.invokeMapMethod<String, dynamic>('environment') ??
          const {};
    } on MissingPluginException {
      // Desktop, or a test host. The Dart half below still reports the build.
    } on PlatformException {
      // A device that refuses to answer should cost the user a few lines of
      // detail, not their report.
    }

    final fields = <String, String>{};
    final version = _value(platform['versionName']);
    final code = _value(platform['versionCode']);
    fields['App version'] = version == null
        ? unknown
        : (code == null ? version : '$version (build $code)');
    fields['Package'] = _value(platform['packageName']) ?? unknown;
    fields['Build mode'] = kReleaseMode
        ? 'release'
        : kProfileMode
            ? 'profile'
            : 'debug';
    fields['Engine'] = Platform.version;
    fields['Installed from'] = _value(platform['installer']) ?? unknown;

    final manufacturer = _value(platform['manufacturer']);
    final model = _value(platform['model']);
    final device = _value(platform['device']);
    if (model != null) {
      final brand = manufacturer ?? _value(platform['brand']);
      fields['Device'] = [
        if (brand != null) '$brand $model' else model,
        if (device != null && device != model) '($device)',
      ].join(' ');
    }

    final release = _value(platform['androidRelease']);
    if (release != null) {
      final sdk = _value(platform['sdkInt']);
      final patch = _value(platform['securityPatch']);
      // A `userdebug` or `eng` image is not what a phone normally runs, and it
      // explains a whole class of odd behaviour without anyone having to ask.
      final type = _value(platform['buildType']);
      fields['Android'] = [
        release,
        if (sdk != null) '(API $sdk)',
        if (patch != null) 'patch $patch',
        if (type != null && type != 'user') '($type build)',
      ].join(' ');
    } else {
      // Not Android: the Dart view of the OS is all there is.
      fields['OS'] = '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    }

    final abis = _value(platform['abis']);
    if (abis != null) {
      final installed = _value(platform['nativeAbi']);
      fields['CPU'] = [
        abis,
        if (installed != null) 'build runs $installed',
        '${Platform.numberOfProcessors} cores',
      ].join(' · ');
    }
    if (platform['emulator'] == true) fields['Emulator'] = 'yes';
    if (platform['debuggable'] == true) fields['Debuggable'] = 'yes';

    final totalRam = _int(platform['totalRamMb']);
    if (totalRam != null) {
      fields['RAM'] = '${_mb(totalRam)}${platform['lowRam'] == true ? ' (low-RAM device)' : ''}';
    }
    final freeStorage = _int(platform['freeStorageMb']);
    final totalStorage = _int(platform['totalStorageMb']);
    if (freeStorage != null) {
      fields['Storage'] = totalStorage == null
          ? '${_mb(freeStorage)} free'
          : '${_mb(freeStorage)} free of ${_mb(totalStorage)}';
    }

    fields['Locale'] = Platform.localeName;
    fields.addAll(extra);
    return EnvironmentInfo(fields);
  }

  /// The report's own view of itself: `Label: value` lines, skipping what this
  /// build could not see, so an unknown never looks like a finding.
  List<String> get lines => [
        for (final entry in fields.entries)
          if (entry.value != unknown && entry.value.isNotEmpty)
            '${entry.key}: ${entry.value}',
      ];

  static String? _value(Object? raw) {
    if (raw == null) return null;
    final text = '$raw'.trim();
    return text.isEmpty ? null : text;
  }

  static int? _int(Object? raw) => raw is int ? raw : int.tryParse('$raw');

  /// Whole megabytes are enough here; a report is not a spec sheet.
  static String _mb(int megabytes) =>
      megabytes >= 1024 ? '${(megabytes / 1024).toStringAsFixed(1)} GB' : '$megabytes MB';
}

/// A conversion that did not finish, in the form a report carries it.
///
/// Read back from history rather than handed over by a live job, so a tester
/// can report a failure from yesterday — after the app has been restarted,
/// which is exactly when they get round to it.
class FailureRecord {
  const FailureRecord({
    required this.pair,
    required this.name,
    required this.at,
    this.error,
    this.detail,
    this.sourceBytes = 0,
    this.outputBytes = 0,
    this.elapsedMs = 0,
  });

  final String pair;

  /// The file's name only. Never its path: a report is shared with someone
  /// else, and the folders a file lives in say more about the tester than the
  /// bug does.
  final String name;
  final DateTime at;
  final String? error;
  final String? detail;
  final int sourceBytes;
  final int outputBytes;
  final int elapsedMs;

  factory FailureRecord.fromEntry(HistoryEntry entry) => FailureRecord(
        pair: entry.pairLabel,
        name: entry.name,
        at: entry.createdAt,
        error: entry.error,
        detail: entry.errorDetail,
        sourceBytes: entry.sourceBytes,
        outputBytes: entry.outputBytes,
        elapsedMs: entry.elapsedMs,
      );

  /// One failure, as the report prints it. [index] numbers them so a tester can
  /// point at the one they mean.
  List<String> lines(int index) {
    final out = <String>[
      '$index. $pair — $name — ${stamp(at)}',
    ];
    if (error != null && error!.trim().isNotEmpty) {
      out.add('   Failed: ${_singleLine(redactPaths(error!))}');
    }
    out.add(
      '   Source ${humanBytes(sourceBytes)}, output ${humanBytes(outputBytes)}, '
      'after ${humanDuration(Duration(milliseconds: elapsedMs))}',
    );
    final tail = detail?.trim();
    if (tail != null && tail.isNotEmpty) {
      out.add('   Engine output:');
      // The tail is where the reason is, but a whole FFmpeg log would bury the
      // rest of the report. The end of the log is the part that fails.
      final clipped = tail.length > detailLimit
          ? '… (earlier output cut)\n${tail.substring(tail.length - detailLimit)}'
          : tail;
      out.addAll(redactPaths(clipped).split('\n').map((l) => '     $l'));
    }
    return out;
  }

  /// How much engine output one failure may contribute.
  static const int detailLimit = 2000;
}

/// Builds the report a tester sends: what they typed, what the app knows about
/// the device, and the failures behind it.
///
/// Plain text on purpose. It lands in an email, a chat message or a bug report,
/// and all three read plain text better than anything else — and the tester can
/// see every word of it before it leaves the phone.
String buildFailureReport({
  required EnvironmentInfo environment,
  List<FailureRecord> failures = const [],
  String message = '',
  DateTime? at,
  Map<String, String> symptoms = const {},
  String? failuresNote,
}) {
  final when = at ?? DateTime.now();
  final buffer = StringBuffer()
    ..writeln('$productName — failure report')
    ..writeln(stamp(when))
    ..writeln()
    ..writeln('What the tester reported')
    ..writeln('-----------------------')
    ..writeln(message.trim().isEmpty ? '(nothing typed — see the failures below)' : message.trim());

  if (symptoms.isNotEmpty) {
    // The screen that opened the report knows things the device does not: which
    // conversion was on it, which options it was run with. Worth more to a
    // triage than any amount of model number.
    buffer
      ..writeln()
      ..writeln('Where it happened')
      ..writeln('-----------------');
    symptoms.forEach((label, value) => buffer.writeln('$label: $value'));
  }

  buffer
    ..writeln()
    ..writeln('Device and build')
    ..writeln('----------------');
  final lines = environment.lines;
  if (lines.isEmpty) {
    buffer.writeln('(nothing could be read on this device)');
  } else {
    lines.forEach(buffer.writeln);
  }

  buffer
    ..writeln()
    ..writeln('Recent failures')
    ..writeln('---------------');
  if (failures.isEmpty) {
    // "None recorded" would be a claim, and a history that could not be read
    // is not the same thing as a history with nothing in it.
    buffer.writeln(failuresNote ?? '(none recorded)');
  } else {
    for (var i = 0; i < failures.length; i++) {
      failures[i].lines(i + 1).forEach(buffer.writeln);
      if (i != failures.length - 1) buffer.writeln();
    }
  }

  buffer
    ..writeln()
    ..writeln('---')
    ..writeln(
      'Written by $productName on the device. Nothing was uploaded: the app has '
      'no analytics and never asks for network access. No file contents are '
      'included, and the folder paths an engine log mentions are trimmed back '
      'to the file name.',
    );
  return buffer.toString();
}

/// Strips the folders off any file path an engine printed, keeping the file
/// name.
///
/// An FFmpeg log quotes the full path of what it was reading, which says where
/// on someone's phone their files live — often with their own name in a folder
/// called "Tax 2025 - J. Smith". That has nothing to do with the bug, and a
/// report is written by the user but read by someone else, so the folders go
/// before it is ever shown to them. The name stays: it is the one part that
/// identifies which file failed.
///
/// Only paths under a filesystem root are touched, so version strings, MIME
/// types and marker names in a log survive intact.
String redactPaths(String text) {
  const roots = [
    '/data/',
    '/storage/',
    '/sdcard/',
    '/mnt/',
    '/system/',
    '/proc/',
    '/vendor/',
    '/odm/',
  ];

  return text.split('\n').map((line) {
    var start = -1;
    for (final root in roots) {
      final at = line.indexOf(root);
      if (at >= 0 && (start < 0 || at < start)) start = at;
    }
    if (start < 0) return line;
    // Everything from the last slash on is kept, not just the next segment: a
    // folder name can contain spaces, and the message after a path is worth
    // keeping.
    final lastSlash = line.lastIndexOf('/');
    // Nothing after the slash means there is no file name to keep, so there is
    // nothing to gain by rewriting a bare directory.
    if (lastSlash < start || lastSlash == line.length - 1) return line;
    return '${line.substring(0, start)}…/${line.substring(lastSlash + 1)}';
  }).join('\n');
}

/// `2026-09-19 14:03`, in the offset the device is actually in.
String stamp(DateTime at) {
  final local = at.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}


/// The engine's message, flattened: a multi-line FFmpeg complaint would break
/// the one-line summary it is being put into.
String _singleLine(String value) =>
    value.trim().split(RegExp(r'\s*\n\s*')).join(' ').trim();
