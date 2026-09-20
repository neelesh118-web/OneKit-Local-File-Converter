import 'package:flutter/services.dart';

import '../../engine/format.dart';

/// The public collection a converted file belongs in.
///
/// The names are what the platform side switches on, and they match the four
/// collections the phone's own apps read: the gallery's pictures and videos, the
/// music apps' audio, and the Downloads app for everything that is not media at
/// all — a PDF, a CSV, a ZIP.
enum MediaCollection { images, video, audio, downloads }

/// Why a copy into the phone's own storage did not happen.
///
/// The wording is here rather than on the platform side, so the app has one
/// vocabulary for it, and it is deliberately quiet: the conversion succeeded
/// and its result is still in the app's own folder, so this is a note about a
/// second copy, never a failure.
enum MediaExportReason {
  /// Android 9 or older, where the same write would need a storage permission
  /// this app does not request and will not.
  unsupported,

  /// The finished file could not be read back.
  unreadable,

  /// The phone's media store declined the entry.
  refused,

  /// Something else went wrong part-way through the copy.
  failed;

  String get message => switch (this) {
        MediaExportReason.unsupported =>
          'A copy in your Gallery needs Android 10 or newer. This file is in the app\'s own folder.',
        MediaExportReason.unreadable =>
          'The finished file could not be read back to copy it. It is in the app\'s own folder.',
        MediaExportReason.refused =>
          'Your phone would not take a copy. The file is in the app\'s own folder.',
        MediaExportReason.failed =>
          'The copy into your Gallery did not finish. The file is in the app\'s own folder.',
      };
}

/// What became of one attempt to make a finished file visible to the rest of
/// the phone.
class MediaExportResult {
  const MediaExportResult.saved(this.location) : reason = null;

  const MediaExportResult.notSaved(this.reason) : location = null;

  /// The public folder the copy landed in, e.g. `Pictures/OneKit`. Null when
  /// there is no copy.
  final String? location;

  /// Set only when [saved] is false.
  final MediaExportReason? reason;

  bool get saved => location != null;

  /// Reads the platform's answer. Anything unrecognisable is a copy that did
  /// not happen, which is the safe direction to fail in: the app then says the
  /// file is in its own folder, which is where it certainly is.
  static MediaExportResult fromChannel(Object? payload) {
    if (payload is! Map) return const MediaExportResult.notSaved(MediaExportReason.failed);
    final location = payload['location'];
    if (payload['saved'] == true) {
      return MediaExportResult.saved(
        location is String && location.isNotEmpty ? location : 'your Gallery',
      );
    }
    return MediaExportResult.notSaved(switch (payload['reason']) {
      'unsupported' => MediaExportReason.unsupported,
      'unreadable' => MediaExportReason.unreadable,
      'refused' => MediaExportReason.refused,
      _ => MediaExportReason.failed,
    });
  }
}

/// Makes a finished conversion visible to the phone's own apps.
///
/// A conversion is written inside the app's private folder, because that is the
/// only place it may write without asking for a permission. That is also a place
/// no gallery, Downloads app or file manager lists, so a converted photo is
/// findable only from inside OneKit — which is not where anyone looks for it.
/// This copies the result into MediaStore instead, under a folder named after
/// the app, so the system's own apps show it beside everything else.
///
/// The copy is a copy, not a move: the app's Files screen, its history and its
/// share flow all still work off the original, which is what keeps this from
/// being a change to how the app works rather than an addition to it.
///
/// Everything here answers "not saved" on a platform with no such channel, and
/// never throws for it: a desktop build, and the host test suite, have no media
/// store to copy into. That absence is not a failure worth showing anyone, just
/// a copy that did not happen.
class MediaExport {
  MediaExport._();

  static final MediaExport instance = MediaExport._();

  static const _methods = MethodChannel('onekit/media_store');

  /// Which collection a target of [family] belongs in. Never null: anything the
  /// gallery would not show — documents, data, archives, fonts — goes to
  /// Downloads, where a file manager will.
  static MediaCollection collectionFor(Family family) => switch (family) {
        Family.image => MediaCollection.images,
        Family.video => MediaCollection.video,
        Family.audio => MediaCollection.audio,
        Family.document ||
        Family.data ||
        Family.archive ||
        Family.ebook ||
        Family.subtitle ||
        Family.font ||
        Family.vector =>
          MediaCollection.downloads,
      };

  /// Copies [path] into the phone's own storage, returning where it landed.
  ///
  /// Never throws and never reports the conversion itself as failed: a file
  /// that has already been written and shown to the user does not become a
  /// failure because a second copy of it could not be made.
  Future<MediaExportResult> publish({
    required String path,
    required String name,
    required Family family,
    String? mime,
  }) async {
    try {
      final payload = await _methods.invokeMethod<Object?>('publish', {
        'path': path,
        'name': name,
        'mime': mime == null || mime.isEmpty ? 'application/octet-stream' : mime,
        'collection': collectionFor(family).name,
      });
      return MediaExportResult.fromChannel(payload);
    } on MissingPluginException {
      // No channel behind the call. Android 9 and older answers this way too,
      // from the other side of the same wall: no MediaStore write without a
      // permission this app does not ask for.
      return const MediaExportResult.notSaved(MediaExportReason.unsupported);
    } on PlatformException {
      return const MediaExportResult.notSaved(MediaExportReason.failed);
    }
  }
}
