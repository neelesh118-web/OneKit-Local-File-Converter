# 100% Local File Converter

A file converter for Android that runs **entirely on the device**. No upload, no
server, no account, no size limit beyond your own storage.

**5,890 conversions across 148 formats**, generated from a capability registry
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
| Font | 4 | TTF, OTF, TTC, WOFF — collection extraction and WOFF container work |

Plus cross-family routes: video → audio, video → image/GIF, image → video,
image → PDF, PDF → image/text/data/EPUB, document → eBook, subtitle → data.

SVG and JPEG XL are deliberately **not** listed: the bundled engines cannot
rasterise SVG and this FFmpeg build has no libjxl, so nothing in the app could
read them. The registry is only allowed to advertise routes a converter
actually claims, and a test asks FFmpeg directly which codecs it contains and
fails if the catalogue overstates it.

The same rule shapes the font family. TTC, WOFF, TTF and OTF are all sfnt
containers, so extracting a collection's face or packing WOFF's zlib tables
is honest container work — but TTF ↔ OTF means translating glyph outlines
(quadratic glyf versus cubic CFF), which is font compiling. Those two pairs
are the only ones removed from the matrix by hand, and the converter still
refuses at run time to label a face with the wrong outline format.

## Features

- **Single convert** — pick a file, see every format it can become, watch a real
  percentage (from ffmpeg's own statistics stream, never a fake timer).
- **Batch** — many files at once, one shared target, honest overall progress.
- **Bulk ZIP** — drop in a ZIP and the app converts everything inside it, then
  packs the results back into a ZIP.
- **History** — every conversion, with time taken and space saved.
- **Files** — a file manager over the output folder: search, sort, multi-select,
  share, delete, or re-convert.
- **Per-format options** — quality, resize, bitrate, sample rate, CRF, frame
  rate, PDF page ranges and render DPI, metadata stripping.
- **Built-in previews** — converting to QOI or DPX should not mean you can
  never look at the result. The app renders previews itself: images and video
  frames and PDF pages, the opening lines of text and data files, and the
  contents of archives. No other app required.
- **Monochrome design** — the light and dark themes are exact inversions of one
  another, over a pulsing starfield that accelerates while a conversion runs.

## Speed

Measured on a physical mid-range phone in profile mode
(`integration_test/benchmark_test.dart`):

| Conversion | Before | After |
| --- | --- | --- |
| 12 MP PNG → JPG | 23.6 s | **2.7 s** |
| MKV → MP4 (H.264 inside) | full re-encode | **447 ms** |
| MP4 → MKV | full re-encode | **414 ms** |
| Release APK | 121 MB | **87 MB** |

Three things got it there:

1. **Remux instead of re-encode.** If the encoded stream already suits the
   target container, it is copied rather than transcoded — instant, and
   lossless, so quality improves too.
2. **The pure-Dart image path was deleted.** It was written to avoid a native
   round trip and measured 9x *slower* than FFmpeg on a real photo.
3. **Hardware encoding.** Where a re-encode is genuinely needed, the phone's
   own MediaCodec encoder is tried first, falling back to software silently if
   the chipset refuses.

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
      font_converter.dart     TTC / WOFF / sfnt container work
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

Run it in **profile mode**, not debug:

```bash
flutter drive --driver=test_driver/integration_test.dart   --target=integration_test/format_matrix_test.dart --profile
```

Debug is JIT and release is AOT, and they disagree. An isolate closure that
captured its `ConvertRequest` — and with it a `CancelToken` holding callbacks —
passed every debug run and failed every conversion in the shipped APK. Only an
AOT run catches that class of bug.

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

This app bundles `ffmpeg_kit_flutter_new`, which ships the **full-GPL** FFmpeg
build (x264, x265, libwebp, libaom, OpenJPEG). That gives the widest format
coverage, and it means distributing the app carries **GPLv3 obligations**. The
app is open-source, so this is fully compliant — source code is available at
the repository URL.

## Privacy

There is no network code in the conversion path. The only outbound traffic in
the whole app is AdMob. History and settings live in app-private storage.
