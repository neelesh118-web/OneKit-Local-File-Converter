import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// A file another app handed to OneKit.
///
/// [path] is a real path in the app's own scratch space, because Android gives
/// the file over as a `content://` URI that only this app can read, and the
/// conversion engines work on files. [name] is the name the sending app showed
/// the user, which is what belongs in the UI.
class SharedFile {
  const SharedFile({required this.path, required this.name});

  final String path;
  final String name;

  /// Reads one entry of the platform payload, ignoring anything malformed: a
  /// share that arrives half-formed should be dropped, not crash the app on
  /// launch.
  static SharedFile? fromChannel(Object? entry) {
    if (entry is! Map) return null;
    final path = entry['path'];
    if (path is! String || path.isEmpty) return null;
    final name = entry['name'];
    return SharedFile(
      path: path,
      // basename, not a split on the platform separator: the path arrives from
      // Android but this runs wherever the app does, and the host tests are not
      // on Android at all.
      name: name is String && name.isNotEmpty ? name : p.basename(path),
    );
  }

  /// Parses a whole payload, which is always a list of those entries.
  static List<SharedFile> listFromChannel(Object? payload) {
    if (payload is! List) return const [];
    final out = <SharedFile>[];
    for (final entry in payload) {
      final file = fromChannel(entry);
      if (file != null) out.add(file);
    }
    return out;
  }
}

/// Files other apps share into OneKit, through Android's SEND, SEND_MULTIPLE and
/// VIEW intents.
///
/// The platform side does the copying — a shared file is only readable by the
/// app that was handed the URI, and only until the activity goes away — and this
/// class turns the result into [SharedFile]s. Everything here is a no-op on a
/// platform that has no such channels, which is why the desktop build of the
/// test suite still runs.
class ShareIntake {
  ShareIntake._();

  static final ShareIntake instance = ShareIntake._();

  static const _methods = MethodChannel('onekit/share');
  static const _events = EventChannel('onekit/share_events');

  bool get _supported => Platform.isAndroid;

  /// The share that launched the app, if there was one. Consumed on read: the
  /// platform clears its queue, so a hot restart cannot convert the same file
  /// twice.
  Future<List<SharedFile>> takeInitial() async {
    if (!_supported) return const [];
    try {
      final payload = await _methods.invokeMethod<Object?>('takeInitial');
      return SharedFile.listFromChannel(payload);
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  /// Shares that arrive while the app is running. Each event is one handover,
  /// which may carry several files when the user shared a selection.
  Stream<List<SharedFile>> get incoming {
    if (!_supported) return const Stream.empty();
    return _events.receiveBroadcastStream().map(SharedFile.listFromChannel);
  }
}
