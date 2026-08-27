# OneKit — Local File Converter

A file converter for Android that runs **entirely on the device**. No upload, no
server, no account, no size limit beyond your own storage.

**5,935 conversions across 145 formats**, generated from a capability registry
rather than hand-listed, so the catalogue can never advertise something the
engines cannot actually do.

---

## What it converts

| Family | Formats | Notes |
| --- | --- | --- |
| Image | 40 | PNG, JPG, WebP, AVIF, HEIC, TIFF, JP2, QOI, PSD, EXR, ICO … |
| Audio | 33 | MP3, WAV, FLAC, AAC, M4A, OGG, Opus, ALAC, AIFF, WMA … |
| Video | 29 | MP4, MKV, AVI, MOV, WebM, FLV, MPEG-TS, 3GP, OGV … |
| Document | 10 | PDF, DOCX, ODT, RTF, Markdown, HTML, LaTeX, reST, TXT |
| Data | 12 | JSON, CSV, TSV, XML, YAML, NDJSON, INI, TOML, SQL … |
| Archive | 9 | ZIP, TAR, TGZ, TBZ, TXZ, GZ, BZ2, XZ, ZLIB |
| Subtitle | 10 | SRT, VTT, ASS, SSA, SBV, SUB, LRC, TTML, DFXP, SAMI |
| eBook | 2 | EPUB, FB2 |

Plus cross-family routes: video → audio, video → image/GIF, image → video,
image → PDF, PDF → image/text/data/EPUB, document → eBook, subtitle → data.

SVG is deliberately **not** listed: nothing in the bundled engines can
rasterise it, and the registry is only allowed to advertise routes a converter
actually claims — a rule enforced by a test.

## Features

- **Single convert** — pick a file, see every format it can become, watch a real
  percentage (from ffmpeg's own statistics stream, never a fake timer).
- **Batch** — many files at once, one shared target, honest overall progress.
- **Bulk ZIP** — drop in a ZIP and OneKit converts everything inside it, then
  packs the results back into a ZIP.
- **History** — every conversion, with time taken and space saved.
- **Files** — a file manager over the output folder: search, sort, multi-select,
  share, delete, or re-convert.
- **Per-format options** — quality, resize, bitrate, sample rate, CRF, frame
  rate, PDF page ranges and render DPI, metadata stripping.
- **Monochrome design** — the light and dark themes are exact inversions of one
  another, over a pulsing starfield that accelerates while a conversion runs.

## Architecture

```
lib/
  engine/
    format.dart              FileFormat / ConversionPair models
    registry.dart            every format + generated pair matrix
    job.dart                 ConversionJob, options, progress
    engine.dart              routes a pair to a converter and runs it
    converters/
      converter.dart         FileConverter interface, CancelToken
      ffmpeg_converter.dart  audio/video/long-tail images
      image_converter.dart   pure-Dart fast path for common images
      document_converter.dart MD/HTML/DOCX/ODT/RTF/reST <-> PDF/LaTeX/…
      data_converter.dart    JSON/CSV/XML/YAML/INI/TOML/SQL
      subtitle_converter.dart 10 subtitle formats via a Cue pivot
      archive_converter.dart  containers and single streams
      pdf_converter.dart      PDF in and out
      ebook_converter.dart    EPUB/FB2
  core/       theme, widgets (starfield, pulse, brand), ads, storage
  features/   home, convert, batch, history, files, settings, about
```

Every converter declares which pairs it claims. The engine asks each in
priority order and the first match wins, so the specialised pure-Dart backends
sit ahead of the FFmpeg catch-all.

`test/converters_test.dart` runs a real file through every pure-Dart converter
and asserts on the bytes that come back, including a guard that **every
advertised pair resolves to a converter**.

`integration_test/format_matrix_test.dart` covers what the host cannot reach —
FFmpeg and pdfium — by walking the registry on a real device: every decodable
format is read back, every encodable format is written. **213/213 pass.**

That pass rate took three rounds. The first found 17 broken conversions, which
is exactly the point: ALAC needed an MP4 container, AMR and GSM are 8 kHz mono
only, DTS is an experimental encoder, 3GP needs baseline H.264 with AAC, DV and
MXF have fixed broadcast geometry, and the bundled FFmpeg writes VP9 that its
own decoder rejects (WebM and IVF are written as VP8 instead). Three encoders —
farbfeld, libgsm and 8SVX — are simply absent from this build, so those formats
are now read-only rather than advertised and broken.

### Known limitation

PDF output uses the built-in PDF base fonts, which are Latin-1 only. Non-Latin
text (Devanagari, CJK, Cyrillic, …) will not render in generated PDFs until a
Unicode font is bundled.

## Build

```bash
flutter pub get
flutter test
flutter build appbundle --release   # Play Store
flutter build apk --release         # sideload
```

Release signing reads `android/key.properties` (git-ignored):

```properties
storePassword=…
keyPassword=…
keyAlias=onekit
storeFile=../onekit-release.jks
```

Without that file the release build falls back to debug keys so a fresh clone
still compiles.

## Licensing note

OneKit bundles `ffmpeg_kit_flutter_new`, which ships the **full-GPL** FFmpeg
build (x264, x265, libwebp, libaom, OpenJPEG). That gives the widest format
coverage, and it means distributing the app carries **GPLv3 obligations**. If
you need to ship closed-source, swap to an LGPL FFmpeg build — the trade-off is
losing H.264/H.265 encoding.

## Privacy

There is no network code in the conversion path. The only outbound traffic in
the whole app is AdMob. History and settings live in app-private storage.
