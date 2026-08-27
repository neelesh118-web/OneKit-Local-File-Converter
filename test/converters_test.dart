import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onekit_converter/engine/converters/archive_converter.dart';
import 'package:onekit_converter/engine/converters/converter.dart';
import 'package:onekit_converter/engine/converters/data_converter.dart';
import 'package:onekit_converter/engine/converters/document_converter.dart';
import 'package:onekit_converter/engine/converters/ebook_converter.dart';
import 'package:onekit_converter/engine/converters/subtitle_converter.dart';
import 'package:onekit_converter/engine/engine.dart';
import 'package:onekit_converter/engine/format.dart';
import 'package:onekit_converter/engine/job.dart';
import 'package:onekit_converter/engine/registry.dart';
import 'package:path/path.dart' as p;

/// Exercises every converter that does not need a device or native library, by
/// running a real file through it and reading the result back.
void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('onekit_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  FileFormat fmt(String ext) => FormatRegistry.byExt(ext)!;

  /// Runs [converter] over [input] and returns the output file.
  Future<File> run(
    FileConverter converter,
    File input,
    String toExt, {
    ConvertOptions options = const ConvertOptions(),
  }) async {
    final out = File(p.join(tmp.path, 'out.$toExt'));
    final progress = <double>[];
    await converter.convert(
      ConvertRequest(
        inputPath: input.path,
        outputPath: out.path,
        from: fmt(p.extension(input.path).replaceFirst('.', '')),
        to: fmt(toExt),
        options: options,
        cancel: CancelToken(),
        extraOutputs: [],
        onProgress: (v, {bool indeterminate = false}) => progress.add(v),
      ),
    );
    expect(out.existsSync(), isTrue, reason: 'no output written for .$toExt');
    expect(
      out.lengthSync(),
      greaterThan(0),
      reason: 'empty output for .$toExt',
    );
    // Progress must reach 1.0 and never run backwards.
    expect(progress.last, 1.0);
    for (var i = 1; i < progress.length; i++) {
      expect(progress[i], greaterThanOrEqualTo(progress[i - 1]));
    }
    return out;
  }

  File write(String name, String content) =>
      File(p.join(tmp.path, name))..writeAsStringSync(content);

  // ------------------------------------------------------------------ data

  group('DataConverter', () {
    const converter = DataConverter();

    test('CSV to JSON keeps rows, headers and numeric types', () async {
      final input = write(
        'in.csv',
        'name,age,city\nAda,36,London\nGrace,45,New York\n',
      );
      final out = await run(converter, input, 'json');
      final decoded = jsonDecode(out.readAsStringSync()) as List;
      expect(decoded, hasLength(2));
      expect(decoded.first['name'], 'Ada');
      expect(decoded.first['age'], 36);
      expect(decoded.last['city'], 'New York');
    });

    test('JSON to CSV quotes fields containing the delimiter', () async {
      final input = write(
        'in.json',
        jsonEncode([
          {'a': 'x,y', 'b': 1},
          {'a': 'plain', 'b': 2},
        ]),
      );
      final out = await run(converter, input, 'csv');
      final text = out.readAsStringSync();
      expect(text, contains('"x,y"'));
      expect(text.split('\n').first, 'a,b');
    });

    test('CSV to JSON to CSV round-trips', () async {
      final input = write('in.csv', 'k,v\nalpha,1\nbeta,2\n');
      final json = await run(converter, input, 'json');
      final back = File(p.join(tmp.path, 'back.csv'));
      back.writeAsStringSync(
        DataConverter.serialize(
          DataConverter.parse(json.readAsStringSync(), 'json'),
          'csv',
        ),
      );
      expect(back.readAsStringSync().trim(), input.readAsStringSync().trim());
    });

    test('YAML to JSON handles nesting and lists', () async {
      final input = write(
        'in.yaml',
        'app:\n  name: OneKit\n  tags:\n    - local\n    - fast\n',
      );
      final out = await run(converter, input, 'json');
      final decoded = jsonDecode(out.readAsStringSync()) as Map;
      expect(decoded['app']['name'], 'OneKit');
      expect(decoded['app']['tags'], ['local', 'fast']);
    });

    test('JSON to YAML re-parses to the same tree', () async {
      final original = {
        'name': 'OneKit',
        'count': 3,
        'nested': {'ok': true},
        'list': [1, 2],
      };
      final input = write('in.json', jsonEncode(original));
      final out = await run(converter, input, 'yaml');
      expect(DataConverter.parse(out.readAsStringSync(), 'yaml'), original);
    });

    test('XML to JSON collapses repeated siblings into a list', () async {
      final input = write(
        'in.xml',
        '<rows><row><id>1</id></row><row><id>2</id></row></rows>',
      );
      final out = await run(converter, input, 'json');
      final decoded = jsonDecode(out.readAsStringSync());
      expect(decoded, isA<List>());
      expect((decoded as List), hasLength(2));
    });

    test('JSON to XML produces parsable XML with safe element names', () async {
      final input = write('in.json', jsonEncode({'bad name!': 'v', 'ok': 1}));
      final out = await run(converter, input, 'xml');
      final text = out.readAsStringSync();
      expect(text, contains('<bad_name_>'));
      expect(text, contains('<ok>1</ok>'));
    });

    test('CSV to SQL escapes single quotes', () async {
      final input = write('in.csv', "name\nO'Brien\n");
      final out = await run(converter, input, 'sql');
      expect(out.readAsStringSync(), contains("'O''Brien'"));
    });

    test('INI to JSON keeps sections', () async {
      final input = write('in.ini', '[db]\nhost=localhost\nport=5432\n');
      final out = await run(converter, input, 'json');
      final decoded = jsonDecode(out.readAsStringSync()) as Map;
      expect(decoded['db']['port'], 5432);
    });

    test('TSV to NDJSON emits one object per line', () async {
      final input = write('in.tsv', 'a\tb\n1\t2\n3\t4\n');
      final out = await run(converter, input, 'ndjson');
      final lines = out.readAsStringSync().trim().split('\n');
      expect(lines, hasLength(2));
      expect(jsonDecode(lines.first)['a'], 1);
    });

    test('malformed JSON fails with a message written for a person', () async {
      final input = write('in.json', '{not json');
      await expectLater(
        run(converter, input, 'csv'),
        throwsA(
          isA<ConversionException>().having(
            (e) => e.message,
            'message',
            contains('not valid JSON'),
          ),
        ),
      );
    });
  });

  // -------------------------------------------------------------- subtitle

  group('SubtitleConverter', () {
    const converter = SubtitleConverter();
    const srt = '''1
00:00:01,000 --> 00:00:03,500
Hello there

2
00:00:04,000 --> 00:00:06,000
Second line
''';

    test(
      'SRT to VTT rewrites the timing separator and adds the header',
      () async {
        final out = await run(converter, write('in.srt', srt), 'vtt');
        final text = out.readAsStringSync();
        expect(text, startsWith('WEBVTT'));
        expect(text, contains('00:00:01.000 --> 00:00:03.500'));
        expect(text, contains('Hello there'));
      },
    );

    test('SRT to ASS emits a valid script with both dialogue lines', () async {
      final out = await run(converter, write('in.srt', srt), 'ass');
      final text = out.readAsStringSync();
      expect(text, contains('[Script Info]'));
      expect(text, contains('[Events]'));
      expect(RegExp('Dialogue:').allMatches(text), hasLength(2));
    });

    test(
      'every subtitle format round-trips through SRT with timings intact',
      () {
        final cues = SubtitleConverter.parse(srt, 'srt');
        for (final ext in [
          'vtt',
          'ass',
          'ssa',
          'sbv',
          'sub',
          'ttml',
          'dfxp',
          'smi',
        ]) {
          final written = SubtitleConverter.write(cues, ext);
          final reparsed = SubtitleConverter.parse(written, ext);
          expect(reparsed, hasLength(cues.length), reason: '$ext lost cues');
          expect(
            reparsed.first.text,
            cues.first.text,
            reason: '$ext lost text',
          );
          // Formats with coarser time units are allowed a small tolerance.
          expect(
            (reparsed.first.start - cues.first.start).inMilliseconds.abs(),
            lessThanOrEqualTo(60),
            reason: '$ext drifted the start time',
          );
        }
      },
    );

    test('LRC keeps text but only carries start times', () {
      final cues = SubtitleConverter.parse(srt, 'srt');
      final reparsed = SubtitleConverter.parse(
        SubtitleConverter.write(cues, 'lrc'),
        'lrc',
      );
      expect(reparsed.first.text, 'Hello there');
      expect(reparsed.first.start.inMilliseconds, closeTo(1000, 20));
    });

    test('SRT to JSON exposes cues as rows', () async {
      final out = await run(converter, write('in.srt', srt), 'json');
      final rows = jsonDecode(out.readAsStringSync()) as List;
      expect(rows, hasLength(2));
      expect(rows.first['text'], 'Hello there');
      expect(rows.first['startMs'], 1000);
    });

    test('a file with no cues fails clearly', () async {
      await expectLater(
        run(converter, write('in.srt', 'nothing here'), 'vtt'),
        throwsA(isA<ConversionException>()),
      );
    });
  });

  // -------------------------------------------------------------- document

  group('DocumentConverter', () {
    const converter = DocumentConverter();
    const markdown = '''# Title

Some paragraph text.

## Section

- first
- second

> a quote
''';

    test('Markdown to HTML preserves the heading hierarchy and list', () async {
      final out = await run(converter, write('in.md', markdown), 'html');
      final text = out.readAsStringSync();
      expect(text, contains('<h1>Title</h1>'));
      expect(text, contains('<h2>Section</h2>'));
      expect(text, contains('<li>first</li>'));
      expect(text, contains('<blockquote>a quote</blockquote>'));
    });

    test('Markdown to HTML back to Markdown keeps the structure', () async {
      final html = await run(converter, write('in.md', markdown), 'html');
      final blocks = DocumentConverter.readHtmlBlocks(html.readAsStringSync());
      final round = DocumentConverter.writeBlocks(blocks, 'md');
      expect(round, contains('# Title'));
      expect(round, contains('## Section'));
      expect(round, contains('- first'));
    });

    test('Markdown to plain text drops the markup', () async {
      final out = await run(converter, write('in.md', markdown), 'txt');
      final text = out.readAsStringSync();
      expect(text, contains('TITLE'));
      expect(text, isNot(contains('#')));
    });

    test('Markdown to LaTeX escapes special characters', () async {
      final out = await run(
        converter,
        write('in.md', 'Cost is 50% & rising'),
        'tex',
      );
      final text = out.readAsStringSync();
      expect(text, contains(r'\documentclass'));
      expect(text, contains(r'50\% \& rising'));
      expect(text, contains(r'\end{document}'));
    });

    test('Markdown to PDF writes a real PDF header', () async {
      final out = await run(converter, write('in.md', markdown), 'pdf');
      expect(out.readAsBytesSync().sublist(0, 5), utf8.encode('%PDF-'));
    });

    test('HTML to Markdown converts tables', () async {
      final input = write(
        'in.html',
        '<table><tr><td>a</td><td>b</td></tr><tr><td>1</td><td>2</td></tr></table>',
      );
      final out = await run(converter, input, 'md');
      expect(out.readAsStringSync(), contains('| a | b |'));
    });

    test('DOCX text extraction reads paragraphs and heading styles', () async {
      final docx = _buildDocx(tmp, [
        ('Heading1', 'The Title'),
        ('Normal', 'Body copy here.'),
      ]);
      final out = await run(converter, docx, 'md');
      final text = out.readAsStringSync();
      expect(text, contains('# The Title'));
      expect(text, contains('Body copy here.'));
    });

    test('RTF round-trips through plain text', () async {
      final blocks = [const DocBlock('p', 'Hello RTF')];
      final rtfPath = File(p.join(tmp.path, 'in.rtf'))
        ..writeAsStringSync(DocumentConverter.writeBlocks(blocks, 'rtf'));
      final out = await run(converter, rtfPath, 'txt');
      expect(out.readAsStringSync(), contains('Hello RTF'));
    });

    test('Markdown to CSV yields one row per block', () async {
      final out = await run(converter, write('in.md', markdown), 'csv');
      final lines = out.readAsStringSync().trim().split('\n');
      expect(lines.first, 'type,level,text');
      expect(lines.length, greaterThan(4));
    });
  });

  // --------------------------------------------------------------- archive

  group('ArchiveConverter', () {
    const converter = ArchiveConverter();

    File makeZip() {
      final archive = Archive()
        ..addFile(ArchiveFile.string('one.txt', 'first file'))
        ..addFile(ArchiveFile.string('nested/two.txt', 'second file'));
      return File(p.join(tmp.path, 'in.zip'))
        ..writeAsBytesSync(ZipEncoder().encode(archive));
    }

    test('ZIP to TAR keeps every entry and its contents', () async {
      final out = await run(converter, makeZip(), 'tar');
      final archive = TarDecoder().decodeBytes(out.readAsBytesSync());
      final names = archive.files.map((f) => f.name).toSet();
      expect(names, containsAll(['one.txt', 'nested/two.txt']));
      final first = archive.files.firstWhere((f) => f.name == 'one.txt');
      expect(utf8.decode(first.content as List<int>), 'first file');
    });

    test(
      'ZIP to TGZ produces a gzip stream that unpacks back to the entries',
      () async {
        final out = await run(converter, makeZip(), 'tgz');
        final tar = TarDecoder().decodeBytes(
          GZipDecoder().decodeBytes(out.readAsBytesSync()),
        );
        expect(tar.files, hasLength(2));
      },
    );

    test(
      'ZIP to GZ collapses the archive into one compressed stream',
      () async {
        final out = await run(converter, makeZip(), 'gz');
        final raw = GZipDecoder().decodeBytes(out.readAsBytesSync());
        expect(TarDecoder().decodeBytes(raw).files, hasLength(2));
      },
    );

    test('GZ to ZIP wraps the payload as a single named entry', () async {
      final gz = File(p.join(tmp.path, 'payload.txt.gz'))
        ..writeAsBytesSync(GZipEncoder().encode(utf8.encode('plain payload')));
      final out = await run(converter, gz, 'zip');
      final archive = ZipDecoder().decodeBytes(out.readAsBytesSync());
      expect(archive.files, hasLength(1));
      expect(
        utf8.decode(archive.files.first.content as List<int>),
        'plain payload',
      );
    });

    test('GZ to BZ2 preserves the payload byte for byte', () async {
      final gz = File(p.join(tmp.path, 'in.gz'))
        ..writeAsBytesSync(GZipEncoder().encode(utf8.encode('round trip me')));
      final out = await run(converter, gz, 'bz2');
      expect(
        utf8.decode(BZip2Decoder().decodeBytes(out.readAsBytesSync())),
        'round trip me',
      );
    });

    test('a corrupt archive fails with a readable message', () async {
      final bad = File(p.join(tmp.path, 'bad.zip'))
        ..writeAsBytesSync(List.filled(200, 7));
      await expectLater(
        run(converter, bad, 'tar'),
        throwsA(
          isA<ConversionException>().having(
            (e) => e.message,
            'message',
            contains('could not be opened'),
          ),
        ),
      );
    });
  });

  // ----------------------------------------------------------------- ebook

  group('EbookConverter', () {
    const converter = EbookConverter();

    test(
      'Markdown to EPUB builds a container the reader spec expects',
      () async {
        final out = await run(
          converter,
          write('in.md', '# Chapter\n\nSome prose.'),
          'epub',
        );
        final archive = ZipDecoder().decodeBytes(out.readAsBytesSync());
        final names = archive.files.map((f) => f.name).toList();
        expect(names.first, 'mimetype');
        expect(
          utf8.decode(archive.files.first.content as List<int>),
          'application/epub+zip',
        );
        expect(
          names,
          containsAll([
            'META-INF/container.xml',
            'OEBPS/content.opf',
            'OEBPS/nav.xhtml',
          ]),
        );
      },
    );

    test('EPUB back to Markdown recovers the chapter text', () async {
      final epub = await run(
        converter,
        write('in.md', '# Chapter One\n\nSome prose.'),
        'epub',
      );
      final md = await run(converter, epub, 'md');
      final text = md.readAsStringSync();
      expect(text, contains('Chapter One'));
      expect(text, contains('Some prose.'));
    });

    test('an EPUB with no chapters fails clearly', () async {
      final empty = File(p.join(tmp.path, 'empty.epub'))
        ..writeAsBytesSync(
          ZipEncoder().encode(
            Archive()..addFile(ArchiveFile.string('a.txt', 'x')),
          ),
        );
      await expectLater(
        run(converter, empty, 'txt'),
        throwsA(isA<ConversionException>()),
      );
    });
  });

  // ---------------------------------------------------------------- engine

  group('ConversionEngine routing', () {
    test(
      'each pair resolves to exactly one converter, most specific first',
      () {
        expect(
          ConversionEngine.instance.resolve(fmt('png'), fmt('jpg'))!.name,
          'FFmpeg',
        );
        expect(
          ConversionEngine.instance.resolve(fmt('mp4'), fmt('mp3'))!.name,
          'FFmpeg',
        );
        expect(
          ConversionEngine.instance.resolve(fmt('csv'), fmt('json')),
          isA<DataConverter>(),
        );
        expect(
          ConversionEngine.instance.resolve(fmt('srt'), fmt('vtt')),
          isA<SubtitleConverter>(),
        );
        expect(
          ConversionEngine.instance.resolve(fmt('zip'), fmt('tar')),
          isA<ArchiveConverter>(),
        );
        expect(
          ConversionEngine.instance.resolve(fmt('jpg'), fmt('pdf'))!.name,
          'PDF',
        );
        expect(
          ConversionEngine.instance.resolve(fmt('epub'), fmt('txt')),
          isA<EbookConverter>(),
        );
        expect(
          ConversionEngine.instance.resolve(fmt('docx'), fmt('md')),
          isA<DocumentConverter>(),
        );
      },
    );

    test('every advertised pair has a converter that claims it', () {
      final orphans = FormatRegistry.pairs
          .where(
            (pair) => !ConversionEngine.instance.canConvert(pair.from, pair.to),
          )
          .map((pair) => pair.id)
          .toList();
      expect(orphans, isEmpty, reason: 'unroutable pairs: ${orphans.take(20)}');
    });

    test('cancellation is observed before any work begins', () async {
      final cancel = CancelToken()..cancel();
      final job = ConversionJob(
        id: 'x',
        sourcePath: write('in.csv', 'a\n1\n').path,
        target: fmt('json'),
      );
      await ConversionEngine.instance.run(
        job,
        cancel: cancel,
        outputDirectory: tmp.path,
      );
      expect(job.status, JobStatus.cancelled);
    });

    test('a missing source file fails without throwing out of run()', () async {
      final job = ConversionJob(
        id: 'y',
        sourcePath: p.join(tmp.path, 'nope.csv'),
        target: fmt('json'),
      );
      await ConversionEngine.instance.run(
        job,
        cancel: CancelToken(),
        outputDirectory: tmp.path,
      );
      expect(job.status, JobStatus.failed);
      expect(job.error, contains('no longer available'));
    });

    test('output names never collide', () async {
      final source = write('collide.csv', 'a\n1\n');
      for (var i = 0; i < 3; i++) {
        final job = ConversionJob(
          id: '$i',
          sourcePath: source.path,
          target: fmt('json'),
        );
        await ConversionEngine.instance.run(
          job,
          cancel: CancelToken(),
          outputDirectory: tmp.path,
        );
        expect(job.status, JobStatus.done);
      }
      final produced = tmp
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList();
      expect(produced, hasLength(3));
    });

    test('concurrent output reservations never overwrite each other', () async {
      final source = write('parallel.csv', 'a\n1\n');
      final jobs = [
        for (var i = 0; i < 8; i++)
          ConversionJob(
            id: 'parallel-$i',
            sourcePath: source.path,
            target: fmt('json'),
          ),
      ];

      await Future.wait([
        for (final job in jobs)
          ConversionEngine.instance.run(
            job,
            cancel: CancelToken(),
            outputDirectory: tmp.path,
          ),
      ]);

      expect(jobs.every((job) => job.status == JobStatus.done), isTrue);
      final produced = tmp
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList();
      expect(produced, hasLength(8));
      expect(produced.map((f) => f.path).toSet(), hasLength(8));
    });
  });
}

/// Builds a minimal but structurally real DOCX so the extractor is tested
/// against the actual OOXML shape rather than a stub.
File _buildDocx(Directory dir, List<(String style, String text)> paragraphs) {
  final body = paragraphs
      .map(
        (p) =>
            '<w:p><w:pPr><w:pStyle w:val="${p.$1}"/></w:pPr>'
            '<w:r><w:t>${p.$2}</w:t></w:r></w:p>',
      )
      .join();

  const ns =
      'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"';
  final document =
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<w:document $ns><w:body>$body</w:body></w:document>';

  final archive = Archive()
    ..addFile(
      ArchiveFile.string(
        '[Content_Types].xml',
        '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>',
      ),
    )
    ..addFile(ArchiveFile.string('word/document.xml', document));

  return File(p.join(dir.path, 'in.docx'))
    ..writeAsBytesSync(ZipEncoder().encode(archive));
}
