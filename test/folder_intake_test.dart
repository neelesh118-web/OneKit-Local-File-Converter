import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onekit_converter/core/folder/folder_intake.dart';
import 'package:onekit_converter/engine/registry.dart';

/// Taking a whole folder is the one way to reach many files without asking for
/// storage access: the user lends the app a single tree through Android's own
/// picker. What a host can check is the contract with the Android half — what
/// crosses the channel, how the answer is read, and that every format this app
/// can convert survives the platform-side extension filter. What only a device
/// can check is that the picker and the copy work: `integration_test/`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('onekit/folder');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// What Dart sent on the last `pick` call, or null when it sent nothing.
  Map<Object?, Object?>? sent;

  /// Stands in for the Android side, answering every call with [payload].
  void answerWith(Object? payload) {
    sent = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      sent = (call.arguments as Map?)?.cast<Object?, Object?>();
      return payload;
    });
  }

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  /// The Android side's idea of a file's extension, as it actually decides
  /// whether to copy a file: everything after the last dot, lowercased, and
  /// empty when there is no dot to split on. Reproduced here because the whole
  /// extension contract below rests on it, and because a change to it on either
  /// side has to fail these tests rather than a device.
  String platformExtension(String name) {
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  /// Whether the platform would copy a file with this name.
  bool platformWouldCopy(String name) =>
      FolderIntake.readableExtensions.contains(platformExtension(name));

  group('what crosses the channel', () {
    test('the pick carries every extension a converter can read', () async {
      answerWith({'folder': 'Camera', 'files': [], 'skipped': 0, 'root': '/tmp/x'});

      await FolderIntake.instance.pick();

      expect(sent, isNotNull);
      expect(
        (sent!['extensions'] as List).cast<String>().toSet(),
        FolderIntake.readableExtensions.toSet(),
      );
    });

    test('the extensions are the registry\'s readable formats, not a list kept by hand', () {
      final extensions = FolderIntake.readableExtensions;

      expect(extensions, containsAll(FormatRegistry.readable.map((f) => f.ext)));
      expect(extensions, hasLength(extensions.toSet().length),
          reason: 'a duplicate means the list drifted from the registry');
      expect(extensions.every((e) => e == e.toLowerCase() && !e.startsWith('.')),
          isTrue,
          reason: 'the platform compares lowercased names against a single format');
      // The set only ever asks for files the app can open: a name that resolves
      // to a write-only format would be copied in and then refused.
      for (final name in extensions) {
        expect(
          FormatRegistry.byExt(name)?.read,
          isTrue,
          reason: '$name is not the name of anything this build can read',
        );
      }
    });

    test('a format this build cannot read is never asked for', () {
      // Writing these is supported; reading them is not. Copying them into the
      // app's working directory would queue files that cannot be converted.
      expect(FolderIntake.readableExtensions, isNot(contains('sql')));
      expect(FolderIntake.readableExtensions, isNot(contains('tex')));
      expect(FolderIntake.readableExtensions, contains('jpe'),
          reason: 'an alias of a readable format is still a file to take');
      for (final unreadable in FormatRegistry.all.where((f) => !f.read)) {
        expect(
          FolderIntake.readableExtensions,
          isNot(contains(unreadable.ext)),
          reason: '${unreadable.ext} cannot be decoded, so it is not worth copying',
        );
      }
    });

    test('no readable file is filtered out by the platform side', () {
      // The platform keeps a file when the segment after its last dot is in the
      // set it was sent. Every format, and every alias the registry resolves,
      // has to survive that or the user picks a folder and silently loses files.
      for (final format in FormatRegistry.readable) {
        for (final name in [
          'clip.${format.ext}',
          'CLIP.${format.ext.toUpperCase()}',
          for (final alias in format.aliases) 'archive.$alias',
        ]) {
          expect(
            platformWouldCopy(name),
            isTrue,
            reason: '$name resolves to ${format.ext}, which this build can read',
          );
        }
      }
    });

    test('every dotted alias is still reachable by its last segment', () {
      // The reason `gz`, `bz2` and `xz` exist as formats in their own right:
      // without them, `x.tar.gz` would match on `gz`, find nothing, and be
      // skipped even though `tgz` is readable.
      final dotted = [
        for (final format in FormatRegistry.readable)
          for (final alias in format.aliases)
            if (alias.contains('.')) alias,
      ];

      expect(dotted, isNotEmpty, reason: 'the registry does carry such aliases');
      for (final alias in dotted) {
        expect(
          FormatRegistry.byExt(alias)?.read,
          isTrue,
          reason: '$alias resolves to a format this build cannot read',
        );
        expect(
          FolderIntake.readableExtensions,
          contains(alias.split('.').last),
          reason: 'without it, $alias is copied by nobody',
        );
      }
    });
  });

  group('reading the platform\'s answer', () {
    test('the folder, its files and what was left behind', () {
      final pick = FolderPick.fromChannel({
        'folder': 'Camera',
        'root': '/data/cache/lfc_work/folder/17',
        'skipped': 4,
        'files': [
          {'path': '/data/cache/lfc_work/folder/17/holiday.jpg', 'name': 'holiday.jpg'},
          {'path': '/data/cache/lfc_work/folder/17/beach.png', 'name': 'beach.png'},
        ],
      });

      expect(pick.failed, isFalse);
      expect(pick.cancelled, isFalse);
      expect(pick.folder, 'Camera');
      expect(pick.files.map((f) => f.name), ['holiday.jpg', 'beach.png']);
      expect(pick.skipped, 4);
      // The copies are handed back so the screen that asked for them can clear
      // them once the run is over.
      expect(pick.root, '/data/cache/lfc_work/folder/17');
    });

    test('backing out of the picker is an answer, not a failure', () {
      final pick = FolderPick.fromChannel(
        {'files': <Object?>[], 'skipped': 0, 'cancelled': true},
      );

      expect(pick.cancelled, isTrue);
      expect(pick.failed, isFalse);
      expect(pick.problem, isNull);
      expect(pick.files, isEmpty);
    });

    test('a folder nothing in it can be converted from is not a failure', () {
      // An empty result and an unreadable folder are different things: the
      // first is the user's own doing, the second is this app's limit.
      final pick = FolderPick.fromChannel(
        {'folder': 'Notes', 'root': '/tmp/n', 'files': <Object?>[], 'skipped': 6},
      );

      expect(pick.failed, isFalse);
      expect(pick.files, isEmpty);
      expect(pick.skipped, 6);
      expect(pick.folder, 'Notes');
    });

    test('the platform sends a reason, and this side writes the sentence', () {
      expect(
        FolderPick.fromChannel({'problem': 'no space'}).problem,
        contains('not enough room'),
      );
      expect(
        FolderPick.fromChannel({'problem': 'unreadable'}).problem,
        contains('could not be read'),
      );
      // A reason this build does not know is still read as a refusal rather
      // than as nothing having happened.
      final unknown = FolderPick.fromChannel({'problem': 'kettle'});
      expect(unknown.failed, isTrue);
      expect(unknown.problem, isNotNull);
    });

    test('a missing or nonsense answer is treated as a folder that could not be read', () {
      for (final payload in <Object?>[null, 'ok', 42, <Object?>[]]) {
        final pick = FolderPick.fromChannel(payload);
        expect(pick.failed, isTrue, reason: 'for $payload');
        expect(pick.cancelled, isFalse, reason: 'for $payload');
        expect(pick.problem, isNotNull, reason: 'for $payload');
      }
    });

    test('a nameless folder still reads as one', () {
      final pick = FolderPick.fromChannel({'files': <Object?>[], 'skipped': 0});
      expect(pick.failed, isFalse);
      expect(pick.folder, isNotEmpty);
    });

    test('a malformed file entry is dropped, not thrown on', () {
      final pick = FolderPick.fromChannel({
        'folder': 'Camera',
        'skipped': 0,
        'files': [
          {'path': ''},
          'not a map',
          null,
          {'path': '/tmp/keep.png', 'name': 'keep.png'},
        ],
      });

      expect(pick.files.map((f) => f.name), ['keep.png']);
    });
  });

  group('when the picker is not there', () {
    test('no channel at all is a refusal, never a thrown exception', () async {
      messenger.setMockMethodCallHandler(channel, null);

      final pick = await FolderIntake.instance.pick();

      expect(pick.failed, isTrue);
      expect(pick.cancelled, isFalse);
      expect(pick.files, isEmpty);
      // A desktop build has no folder picker, and the sentence says what to do
      // instead rather than naming a platform.
      expect(pick.problem, contains('Add files'));
    });

    test('a platform that throws is a refusal too', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'nope');
      });

      final pick = await FolderIntake.instance.pick();

      expect(pick.failed, isTrue);
      expect(pick.problem, isNotNull);
    });

    test('a cancelled pick is not a refusal even through the channel', () async {
      answerWith({'files': <Object?>[], 'skipped': 0, 'cancelled': true});

      final pick = await FolderIntake.instance.pick();

      expect(pick.cancelled, isTrue);
      expect(pick.failed, isFalse);
    });
  });
}
