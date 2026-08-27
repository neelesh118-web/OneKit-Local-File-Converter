# Play Store listing — OneKit

## App name (30 chars max)

```
OneKit - Local File Converter
```
*(29 characters)*

## Short description (80 chars max)

```
Convert 5,900+ file formats offline. No upload, no account, nothing leaves you.
```
*(78 characters)*

## Full description (4000 chars max)

```
OneKit converts your files on your phone. Not on a server somewhere — on your
device, with no upload, no account and no waiting in a queue.

That one decision changes everything about how a converter behaves. Your files
stay private. It works on a plane, on the metro, on no signal at all. There is
no 100 MB cap, no daily limit, and no "upgrade to convert this one".

5,935 CONVERSIONS, 145 FORMATS

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

And the conversions people actually search for: HEIC to JPG, MP4 to MP3,
WebP to PNG, PDF to JPG, JPG to PDF, DOCX to PDF, MKV to MP4, CSV to JSON,
SRT to VTT, ZIP to TAR.

WHAT IT DOES

Select a file — OneKit works out every format it can become, and shows you
only those. No dead ends.

Batch convert — queue up dozens of files and convert them all to one format,
with a real progress bar for the batch and for each file.

Bulk ZIP — hand OneKit a ZIP and it converts everything inside, then packs the
results back into a new ZIP for you.

Real progress — the percentage you see comes from the encoder itself, not from
a spinner pretending to work. When a format genuinely has nothing to measure,
OneKit says so instead of inventing a number.

Fine control — quality, resize, bitrate, sample rate, video quality, frame
rate, PDF page ranges and render density, and a switch to strip EXIF, location
and other metadata from the output.

History — everything you have converted, with how long it took and how much
space you saved.

Files — a built-in file manager for your converted files: search, sort,
select several, share, delete, or convert them again.

DESIGN

Pure black and white, in both directions: white buttons on black in dark mode,
black buttons on white in light mode. A field of stars drifts and pulses
behind everything, and picks up speed while a conversion runs.

PRIVACY

There is no server. There is no sign-in. There is no analytics on your files.
The conversion code never touches the network — the only thing in the app that
does is the ad banner. Your history and settings live in private app storage
and go nowhere.

OneKit is free. If it saves you time, there is a tip jar in Settings.
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
*shared*: OneKit reads the file the user picks and writes the result back to
the device. Nothing is transmitted.

## Permissions and why

| Permission | Reason |
| --- | --- |
| `INTERNET` | AdMob only |
| `ACCESS_NETWORK_STATE` | Required by the Google Mobile Ads SDK |
| `AD_ID` | AdMob on Android 13+ |
| `WAKE_LOCK` | Keeps long video and batch conversions running |

No storage permission is requested: files come in through the system picker
and results are written to app-private storage, then shared out via the
system share sheet.

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
- [x] Every conversion path exercised on a physical device (213/213)
- [x] End-to-end conversion verified in the signed release build
- [ ] Privacy policy URL — **required**, the app shows ads
- [ ] Decide on the FFmpeg licence build (see README) — **blocks publishing**
