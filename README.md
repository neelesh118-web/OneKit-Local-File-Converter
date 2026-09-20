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

The same rule keeps **Optimize** honest. Re-encoding a file into its own format
is a real capability, but "JPG to JPG" is not a conversion, so no self-pair ever
enters the matrix or the target picker: the converters declare
`supportsOptimize` separately, the engine asks them directly, and a format is
only offered when it can both be decoded *and* encoded — which is what leaves
HEIC, DDS and WAV out. 61 of the 148 formats qualify.

The same rule shapes the font family. TTC, WOFF, TTF and OTF are all sfnt
containers, so extracting a collection's face or packing WOFF's zlib tables
is honest container work — but TTF ↔ OTF means translating glyph outlines
(quadratic glyf versus cubic CFF), which is font compiling. Those two pairs
are the only ones removed from the matrix by hand, and the converter still
refuses at run time to label a face with the wrong outline format.

## Features

- **Single convert** — pick a file, see every format it can become, watch a real
  percentage (from ffmpeg's own statistics stream, never a fake timer).
- **Optimize** — shrink a file without changing what it is. JPG, PNG, WebP,
  MP4, MP3 and 56 other formats re-encode into themselves at a lower quality,
  a smaller size, or with the metadata stripped, and the result screen reports
  honestly when a re-encode came out *larger* instead of hiding it.
- **Share in** — send a file to OneKit from any app's share sheet, or hand it
  over with "Open with" from Files. Several files shared at once land in Batch.
  This adds **no permission**: Android hands the app a temporary read grant on
  the URI it was given, the file is copied into the app's own scratch space, and
  that copy is cleared by Settings' "Clear working files" along with everything
  else. The Open-with list is deliberately curated rather than `*/*` — OneKit
  offers itself for the formats it can actually convert, not for everything on
  the device.
- **Batch** — many files at once, honest overall progress, and a choice of what
  the batch does: convert everything to one format, or **Optimize each**, which
  re-encodes every file into its own format at one shared quality. The second is
  how a mixed queue gets smaller — a folder of photos, a folder of clips, or a
  ZIP that came out of neither — because there is no format they all share to be
  converted into. Files this build cannot re-encode (lossless audio, or a format
  with no encoder in it) are counted and skipped before the run rather than
  failed one at a time.
- **Bulk ZIP** — drop in a ZIP and the app converts everything inside it, then
  packs the results back into a ZIP.
- **Whole folder** — pick a folder in Android's own picker and everything
  inside it that this build can read is queued, subfolders included. This adds
  **no permission** either: the user lends the app that one folder, and the app
  copies what is in it into its own scratch space, where "Clear working files"
  reaches it. What is *not* copied is as deliberate as what is — a camera
  folder holds thumbnails, `.nomedia` markers and databases beside the photos,
  and only the extensions the app can actually convert are taken, with the rest
  counted and reported rather than copied in and then refused.
- **PDF tools** — merge any number of PDFs, split one by page range or into
  single pages, rotate the pages you name, and compress. The first three are
  pdfium container work: pages are imported, rotated and deleted whole, so
  text, fonts and vectors come through untouched. Compress offers that same
  lossless re-save (it rewrites the file and drops what nothing refers to) and,
  separately, a rasterising mode that really shrinks a scan — labelled for what
  it is, because the text layer does not survive it.
- **History** — every conversion, with time taken and space saved.
- **Failure reports** — when something does not work, the result card offers
  "Send a report". It attaches the device and build it failed on, the engine's
  own output for the failure (FFmpeg's log tail, the decoder's message), and the
  recent failures from history — all of it on screen, in full, before you send
  it. The report is a plain-text file handed to your share sheet; the app never
  posts it anywhere. File names travel with it; the folder paths an engine log
  mentions are trimmed back to the file name first.
- **Keeps going when you leave** — a long video, a forty-file batch or a
  hundred-page PDF render carries on after you switch to another app, which
  Android is otherwise free to kill mid-run. A progress notification says what
  is running and how far along it is, and a second one says what came out, so a
  run that finishes while you were elsewhere does not go unnoticed. Nothing
  depends on the notification: decline it and the conversion still runs.
- **Results where you can find them** — a conversion is written into the app's
  own folder, which is the only place it may write without a permission, and
  which no other app on the phone lists. So a finished result is also copied
  into your Gallery — or into `Download/OneKit` for documents, data, archives
  and anything else a gallery would not show — through Android's own media
  store, which needs no permission either. It is a copy, not a move: Files,
  history and share-out all still work off the original. The result card says
  where the copy went, or why there is not one, and Settings can turn the copy
  off entirely.
- **Files** — a file manager over the output folder: search, sort, multi-select,
  share, delete, or re-convert.
- **Per-format options** — quality, resize, bitrate, sample rate, CRF, frame
  rate, PDF page ranges and render DPI, metadata stripping.
- **Presets** — keep a recipe and reuse it in one tap. Save the target plus the
  settings that suit it ("Web photos", "Smaller, same format"), and it appears as
  a chip on Home and above the target grid. Tapping it sets the recipe and starts
  the job — including optimize recipes, which keep whatever format the next file
  happens to be. A preset is only offered for a file it can actually run on, so a
  recipe saved for videos never appears on a spreadsheet: the applicability rule
  is asked of the engine, exactly as the conversion matrix is.
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
  pdf/
    page_range.dart         the one "1-3,7,10-" parser, shared by converter
                            and toolbox so the syntax cannot mean two things
    pdf_plan.dart           what a toolbox run will write, worked out before
                            any file is touched — and testable on the host
    pdf_toolbox.dart        the pdfium calls that carry the plan out
  core/       theme, widgets (starfield, pulse, brand), ads, storage
              share/  the Dart side of the Android share intake
              folder/  the Dart side of picking a whole folder: the extension
                       contract with the platform, and how every way the pick
                       can come back is read
              media/  the Dart side of the MediaStore copy: which collection a
                      format belongs in, and what the app says when there is
                      no copy to point at
              background/  the progress notification and the foreground
                      service behind it, with the throttle that keeps a
                      progress tick from becoming a system call per frame
              diagnostics/  the failure report: what the device is, what the
                            engine said, and a preview of every word of it
  android/    MainActivity.kt handles SEND / SEND_MULTIPLE / VIEW, copies the
              shared file into the scratch space and hands Dart a path.
              ConversionService.kt holds the process up while a run is going
              and owns the notification; MediaStoreChannel.kt writes the
              Gallery copy; FolderChannel.kt owns the folder picker and walks
              the tree the user lent the app
  features/   home, convert, batch, pdf_tools, history, files, settings, about
```

Every converter declares which pairs it claims. The engine asks each in
priority order and the first match wins, so the specialised pure-Dart backends
sit ahead of the FFmpeg catch-all.

What a queued file becomes is decided in one place
(`features/batch/batch_plan.dart`): the shared target when converting, the
file's own format when optimizing, or nothing at all when this build cannot do
it. The screen's counts and the run loop both read that rule, so the button
cannot promise a file the queue would skip.

`test/converters_test.dart` runs a real file through every pure-Dart converter
and asserts on the bytes that come back, including a guard that **every
advertised pair resolves to a converter**.

The PDF toolbox is split the same way: `pdf_plan.dart` decides which pages go
where and is covered on the host (`test/pdf_tools_test.dart`), while
`pdf_toolbox.dart` only carries the plan out. `integration_test/pdf_tools_test.dart`
runs that second half on a device against real pdfium, and asserts on what comes
back out of the PDF — page counts, the order of the text, the rotation stored on
the page, and whether the text layer survived — rather than on the tool
reporting success.

A preset is a recipe plus the rule for when it applies
(`core/data/preset_store.dart`). It stores a format *extension* rather than a
pair, which is what lets it outlive the file it was made from — and its
applicability is asked of the engine, so a preset that cannot run is kept out of
the chips rather than offered and then failed. The recipe is described by
`ConvertOptions.describe()`, the same method a failure report uses, so one set of
settings never has two vocabularies.

A failure report is assembled in one function that both entry points call, so
Settings and a failed result card cannot send two different things. What the
host can check is the text: that the engine's reason is in it, that a
kilometre-long log is clipped to its tail, and that the folders a path was
found in are not — `test/diagnostics_test.dart`. What only a device can check is
that the Kotlin channel answers at all and that a report can be written where
Settings' "Clear working files" will clean it up: `integration_test/diagnostics_test.dart`.

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

The app requests no storage permission, including for sharing: a file handed
over by another app arrives as a URI with a read grant for OneKit alone. Files
reach the app by the user picking them, sharing them, handing them over with
"Open with", or lending it a whole folder through Android's own folder picker —
never by scanning the device. That folder grant reaches the one tree the user
chose and nothing else, and what is read out of it is copied into the same
working directory the share intake and Settings' "Clear working files" use. The copy that makes a result
visible to the phone's own apps needs no permission either: Android 10 and
above let an app put a file into the media store on its own behalf, so the
Gallery copy adds nothing to the permission list. That copy is the only
thing this app writes anywhere but its own folder, it is made on the device,
and Settings turns it off.

One permission is asked for at run time: notifications, which from Android 13
on is what lets a conversion that is still running say so while the app is off
screen. Declining it costs only that — the run continues, finishes, and is
waiting in Files — and the service that keeps the process alive is the app's
own: not exported, not bound by anything else, and stopped the moment the run
is over.

Nothing about a failure leaves the app on its own either. "Send a report"
writes the plain-text report into the same working directory Settings clears and
hands it to the share sheet; there is no endpoint, no library and no code path
that could post it. It carries the device model, the Android release, the ABI
the installed build runs, the app version and build number, where the build was
installed from, the engine's own reason for each failure, and the file names
involved — no file contents, and not the folders they live in. Every line of it
is on screen before it is sent, so the decision stays with the person who owns
the phone. `test/share_intake_test.dart` fails
the build if a storage permission ever shows up in the manifest without being
stripped.
