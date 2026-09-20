import 'package:flutter/services.dart';

import '../../engine/registry.dart';
import '../share/share_intake.dart';

/// A folder the user picked, and what was taken out of it.
///
/// The files are [SharedFile]s because they are the same thing: a file copied
/// into the app's own scratch space, with the name the user knows it by. Both
/// arrive that way for the same reason — Android hands over a `content://` URI
/// with a read grant for this app alone, and the conversion engines work on
/// paths.
class FolderPick {
  const FolderPick._({
    this.folder,
    this.files = const [],
    this.skipped = 0,
    this.root,
    this.problem,
  });

  /// The user backed out of the picker. An answer, not a failure.
  const FolderPick.cancelled() : this._();

  /// The folder could not be read at all.
  const FolderPick.failed(String problem) : this._(problem: problem);

  /// What was taken out of it.
  const FolderPick.added({
    required String folder,
    required List<SharedFile> files,
    required int skipped,
    String? root,
  }) : this._(folder: folder, files: files, skipped: skipped, root: root);

  /// The picked folder's own name, for the queue rows and the message.
  final String? folder;

  /// The files this build can convert, already copied into its own space.
  final List<SharedFile> files;

  /// Files left behind: nothing here converts them, or they could not be read.
  final int skipped;

  /// Where the copies were put, so whoever asked for them can clear them once
  /// they are done with. Null when nothing was copied.
  final String? root;

  final String? problem;

  bool get cancelled => folder == null && problem == null;
  bool get failed => problem != null;

  /// Reads the platform's answer.
  ///
  /// Anything unrecognisable is treated as a folder that could not be read,
  /// which is the direction that tells the user something: quietly adding
  /// nothing would look like they picked the wrong folder.
  static FolderPick fromChannel(Object? payload) {
    if (payload is! Map) return const FolderPick.failed('That folder could not be read.');
    if (payload['cancelled'] == true) return const FolderPick.cancelled();

    final problem = payload['problem'];
    if (problem != null) return FolderPick.failed(problemFor(problem));

    final folder = payload['folder'];
    return FolderPick.added(
      folder: folder is String && folder.isNotEmpty ? folder : 'folder',
      files: SharedFile.listFromChannel(payload['files']),
      skipped: payload['skipped'] is int ? payload['skipped'] as int : 0,
      root: payload['root'] is String ? payload['root'] as String : null,
    );
  }

  /// The platform's short reason, in the app's words.
  ///
  /// The reason crosses as a fact — `no space`, `unreadable` — and never as a
  /// sentence, so the sentence can be written once, here, beside every other
  /// thing this app says to the person using it.
  static String problemFor(Object? reason) => switch (reason) {
        'no space' => 'There is not enough room on this device to read that folder.',
        _ => 'That folder could not be read.',
      };
}

/// Converting a whole folder, through Android's own folder picker.
///
/// This is the only way to reach a folder full of files without asking for
/// storage access: the user picks one folder in the system's own picker and the
/// app is lent that tree, so nothing else on the device becomes reachable and no
/// permission is involved. What arrives is a tree of `content://` URIs, so the
/// platform side copies what is inside into the app's working directory and
/// hands Dart ordinary paths — exactly the arrangement a shared file arrives
/// under, for exactly the same reason.
class FolderIntake {
  FolderIntake._();

  static final FolderIntake instance = FolderIntake._();

  static const _methods = MethodChannel('onekit/folder');

  /// Every extension a converter can read.
  ///
  /// Asked of the registry rather than listed here, so a format added later is
  /// covered by this without anyone remembering to. It travels with the pick
  /// because the copies are the slow part: a camera folder holds thumbnails,
  /// markers and databases beside the photos, and copying all of it to queue the
  /// photos would be dishonest about what the wait was for.
  ///
  /// Both a format's own extension and every alias it answers to, because the
  /// platform keeps a file by the segment after its last dot and the app then
  /// resolves that name itself. `jpe` is nobody's extension and yet
  /// `photo.jpe` is a JPEG this app converts, so leaving it out would drop files
  /// the user can see in the folder they just picked. Names are filtered through
  /// [FormatRegistry.byExt] so no name here can ever be one the app would refuse
  /// to read — a format's extension outranks another's alias.
  static final List<String> readableExtensions = List.unmodifiable({
    for (final format in FormatRegistry.all)
      for (final name in [format.ext, ...format.aliases])
        if (FormatRegistry.byExt(name)?.read ?? false) name,
  });

  /// Opens Android's folder picker and copies what is inside it.
  ///
  /// Never throws, and never reports a conversion as broken: no picker, a
  /// refused grant, and a user backing out all come back as a [FolderPick] the
  /// calling screen answers in one place.
  Future<FolderPick> pick() async {
    try {
      final payload = await _methods.invokeMethod<Object?>('pick', {
        'extensions': readableExtensions,
      });
      return FolderPick.fromChannel(payload);
    } on MissingPluginException {
      // No such channel: a desktop build, or this test suite.
      return const FolderPick.failed('Picking a whole folder needs Android. Add files instead.');
    } on PlatformException {
      return const FolderPick.failed('Android would not open its folder picker.');
    }
  }
}
