# Play Store listing — 100% Local File Converter

## App name (30 chars max)

```
100% Local File Converter
```
*(29 characters)*

## Short description (80 chars max)

```
Convert 5,800+ file formats offline. No upload, no account, nothing leaves you.
```
*(78 characters)*

## Full description (4000 chars max)

```
This app converts your files on your phone. Not on a server somewhere — on your
device, with no upload, no account and no waiting in a queue.

That one decision changes how a converter behaves. Your files stay private. It
works on a plane, on the metro, on no signal at all. There is no 100 MB cap and
no daily limit.

5,890 CONVERSIONS, 148 FORMATS

• Images — PNG, JPG, WebP, AVIF, HEIC, HEIF, TIFF, BMP, GIF, ICO, JPEG 2000,
  QOI, PSD, EXR, HDR, TGA, PCX, DDS and more
• Audio — MP3, WAV, FLAC, AAC, M4A, OGG, Opus, ALAC, AIFF, WMA, AC3, AMR,
  WavPack, Musepack and more
• Video — MP4, MKV, AVI, MOV, WebM, FLV, WMV, MPEG, 3GP, TS, OGV, MXF and more
• Documents — PDF, DOCX, ODT, RTF, Markdown, HTML, LaTeX, reStructuredText, TXT
• Data — JSON, CSV, TSV, XML, YAML, NDJSON, INI, TOML, SQL
• Archives — ZIP, TAR, TAR.GZ, TAR.BZ2, TAR.XZ, GZ, BZ2, XZ
• Subtitles — SRT, VTT, ASS, SSA, SBV, SUB, LRC, TTML, DFXP, SAMI
• eBooks — EPUB, FB2
• Fonts — TTF, OTF, TTC, WOFF: pull a face out of a collection, pack or
  unpack WOFF for the web

And the conversions people actually search for: HEIC to JPG, MP4 to MP3,
WOFF to TTF, WebP to PNG, PDF to JPG, JPG to PDF, DOCX to PDF, MKV to MP4,
CSV to JSON, SRT to VTT, ZIP to TAR.

WHAT IT DOES

Select a file — the app works out every format it can become, and shows you
only those. No dead ends.

Share a file to it — from the Gallery, from Files, from any share sheet or
"Open with" — and it opens on that file ready to convert, without asking for a
single permission. Share several at once and they land in the batch queue.

Batch convert — queue up dozens of files, or hand it a ZIP and it converts
everything inside, then packs the results back into a new ZIP. Convert them all
to one format, or shrink each one where it is: that keeps every file in its own
format, so a mixed pile of photos, videos and audio gets lighter in one go with
a single quality setting. There is a real progress bar for the batch and for
each file.

Real progress — the percentage you see comes from the encoder itself, not from
a spinner pretending to work. When a format genuinely has nothing to measure,
The app says so instead of inventing a number.

Fine control — quality, resize, bitrate, sample rate, video quality, frame
rate, PDF page ranges and render density, and a switch to strip EXIF, location
and other metadata from the output.

Presets — keep a recipe you use often and run it in one tap: a format plus its
settings, as a chip on the home screen and above the target list.

History — everything you have converted, with how long it took and how much
space you saved.

Files — a built-in file manager for your converted files: search, sort,
select several, share, delete, or convert them again.

Previews — the app shows you the result itself. Convert to an unusual format
and you can still see it, even with no other app on your phone that
understands it.

When something fails — the result card offers a report: your notes, the device
and build it failed on, and the engine's own error output, all on screen before
you send it, and sent only where you choose.

DESIGN

Pure black and white, in both directions: white buttons on black in dark mode,
black buttons on white in light mode. A field of stars drifts and pulses
behind everything, and picks up speed while a conversion runs.

PRIVACY

There is no server. There is no sign-in. There is no analytics on your files.
The conversion code never touches the network — the only thing in the app that
does is the ad banner. Your history, presets and settings live in private app
storage and go nowhere.

Nothing about a failure is sent anywhere either. A report is a text file you
choose to share, it contains no file contents, and the folder paths an error
message mentions are removed before it is even shown to you.

The app is free. If it saves you time, there is a tip jar in Settings.

OPEN SOURCE

The full source code is available — you can verify that nothing leaves your
device.
```

## Category

Tools

## Content rating

Everyone

## Tags

file converter, offline converter, image converter, video converter,
audio converter, PDF converter, HEIC to JPG, MP4 to MP3, local, no upload

## Data safety declaration

| Question | Answer |
| --- | --- |
| Does your app collect or share user data? | **Yes** — advertising only |
| Data types collected | Device or other IDs (advertising ID), via Google AdMob |
| Is data encrypted in transit? | Yes |
| Can users request deletion? | Yes — Android's "Delete advertising ID" control |
| Are files uploaded? | **No.** Conversion is entirely on-device |

Declare **no** file, photo, video, audio, or document access as *collected* or
*shared*: The app reads the file the user picks and writes the result back to
the device. Nothing is transmitted.

## Permissions and why

Verified against the built APK with `aapt2 dump badging`, not just the source
manifest — plugins merge permissions in, and two of them had to be stripped.

| Permission | Reason |
| --- | --- |
| `INTERNET` | AdMob only |
| `ACCESS_NETWORK_STATE` | Required by the Google Mobile Ads SDK |
| `AD_ID`, `ACCESS_ADSERVICES_*` | AdMob on Android 13+ |
| `WAKE_LOCK` | Keeps long video and batch conversions running |
| `FOREGROUND_SERVICE` | Declared by the FFmpeg plugin |

**No storage or media permission is requested.** `READ_EXTERNAL_STORAGE` and
`READ_MEDIA_IMAGES` / `VIDEO` / `AUDIO` were being merged in by the file picker
plugin and are explicitly removed in the manifest. Files reach the app only
through Android's own document picker, its share sheet, or "Open with" — none
of which requires a permission, because Android hands the app a temporary read
grant on the URI it was given — and results are written to app-private storage
and shared out via the system share sheet. Verified on device: picking still
works with all of them removed, and sharing adds nothing to the permission
list (checked against the built APK with `aapt2 dump badging`).

Keeping them would have been untrue to the privacy claim above and would have
pulled the app into Google's **Photo and Video Permissions** policy review for
access it never uses.

## Assets in this folder

| File | Use |
| --- | --- |
| `icon_512.png` | Play Store icon (512×512) |
| `feature_graphic_1024x500.png` | Feature graphic |
| `screenshots/1_splash.png` … `6_settings.png` | Phone screenshots, 720×1640, captured from the signed release build on a physical device |

## Release checklist

- [x] Release keystore generated (`android/onekit-release.jks`, git-ignored)
- [x] `key.properties` wired into `build.gradle.kts`
- [x] Minify + resource shrinking on, with ProGuard keeps for FFmpeg/pdfium/Ads
- [x] AdMob app ID in the manifest
- [x] Production ad unit IDs, with Google test units in debug builds
- [x] Adaptive + monochrome launcher icons
- [x] Native launch screen for light and dark
- [x] Phone screenshots (720×1640, from the signed release build)
- [x] Release AAB built and verified signed (valid to 2056)
- [x] Every conversion path exercised on a physical device (54/54 host + device matrix)
- [x] End-to-end conversion verified in the signed release build
- [x] Privacy policy URL — https://neelesh118-web.github.io/OneKit-Local-File-Converter/
- [x] FFmpeg licence — GPL, source available (open-source app, fully compliant)
