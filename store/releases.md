# Releases

Which artifact is on which track, what is in it, and which commit it came from.
The `versionCode` is what Play keys on and it comes from `pubspec.yaml`, so it is
worth writing down beside the commit — otherwise a build on a track cannot be
traced back to the code that produced it.

**The local `pubspec.yaml` is not evidence of what was uploaded.** A bump that is
never committed still goes into the bundle, which is exactly what happened on
13 September. Read the highest `versionCode` off the track's release list in the
Play Console *before* bumping: Play refuses a code that has been used, and the
refusal arrives after the bundle has been built and signed.

The AAB itself is deliberately **not** in this repository: it is over a hundred
megabytes of something git cannot diff, and `build/` is ignored for that reason.
The paths below are where the copies for upload live. A zipped snapshot of the
whole project, signing material included, is written to `D:\onekit_converter.zip`
alongside the project.

## Closed testing

### Build 4 — versionCode 4 — 2 October 2026, the production build

Production access was granted on 2 October, so this is the first build that
can go to production rather than to the closed test. What it changes:

| | |
| --- | --- |
| Version | `1.1.0+4` (versionName 1.1.0, versionCode 4) |
| Built from | the tree of the commit that added this record and the `+4` bump |
| Signed | upload key `CN=OneKit`, the same keystore as build 3 |
| Copy for upload | `~/Desktop/app-release.aab` |

**The ads were off.** Build 3 shipped with `AdManager.initialize()` commented
out in `lib/main.dart` — a leftover from taking screenshots, on the reasoning
that a screenshot of the app should not have an ad in it. The consequence was
that the whole ad layer was unreachable, and with tree shaking on, no ad unit
string survived into the compiled app at all. That is not an inference:
`tool/release_check.dart` run against build 3's own AAB reports every one of the
five units missing.

Build 4 puts them back, on every screen, and adds what was never there:

- **Ads on all seven screens** — the five tabs, plus Presets, PDF tools, About
  and the report screen. A banner on each, which is the one format that never
  interrupts anything.
- **A native ad row** in History and Files: the SDK's own compact template,
  styled in the app's colours, in the two lists long enough to be scrolled.
- **An interstitial after every third finished run** at most, never twice
  within two minutes, and never while a run is going. A forty-file batch counts
  as one run, not forty.
- **An app-open ad** on a cold launch and on coming back after two minutes
  away, at most once an hour, and skipped entirely while a conversion is still
  running in the background.
- **A rewarded video** in Settings — "Hide ads for an hour" — which is the only
  ad the user chooses to see, and the only way the app will ever show fewer of
  them on request. The hour is remembered across restarts.
- **UMP consent** before the first ad request, with the form reachable again
  from Settings. This was missing from build 3 entirely, which for a production
  release that serves the EEA is the gap that mattered most.
- **A new launcher icon**, drawn by `tool/icon/onekit_icon.dart` rather than
  exported from a design tool, with the adaptive background, foreground and
  monochrome layers all rendered from the same shapes. The old tile was a
  photograph of a laptop; this is the app's own mark on the app's own starfield.

One more thing changed in the ad stack that is not a feature: **the ads are no
longer disabled in debug builds.** Build 3's own comment said ads were off "for
screenshots", which is the kind of switch that stays off. Debug builds request
Google's sample units instead, which is what keeps the real account out of
invalid-traffic trouble, and `test/ad_ids_test.dart` fails if a sample unit ever
reaches the table a release build reads.

### Build 3 — versionCode 3 — built 20 September 2026, uploaded to the closed test

| | |
| --- | --- |
| Version | `1.0.0+3` (versionName 1.0.0, versionCode 3) |
| Built from | the tree of the commit that added this record and the `+3` bump |
| Artifact | `app-release.aab`, 118,785,564 bytes (113.3 MB) |
| SHA-256 | `956e98d53aeba08ebf390c2f83d6d64a310968e4dc2f0a7eba429d27b353966d` |
| Signed | upload key `CN=OneKit`, serial `e97afa60114d2212`, valid to 19 August 2056 |
| Copy for upload | `~/Desktop/LocalFileConverter-1.0.0+3.aab` |
| Build output | `build/app/outputs/bundle/release/app-release.aab` (git-ignored) |

The `versionCode` inside the bundle was read back out of it rather than assumed:
`base/manifest/AndroidManifest.xml` carries `versionCode = 3`, and the merged
manifest agrees. Assuming the number is how the track ended up with a build
whose code was already used.

Nine commits past the build on the track, which is everything a tester has not
seen:

- Optimize, the PDF toolbox, share-in, presets and failure reports (`efd0592`,
  `507a01a`, `9ea61d2`, `eeabd7e`, `bc60e4a`)
- Batch optimize, and the docs for all six (`130de66`, `1bb879c`)
- Even dimensions for animated image targets (`48fd8e6`)
- Gallery copies, background runs and notifications, whole-folder picking, the
  options sheet's Auto fix, and four audit fixes (`2ff9286`)

### Build 2 — versionCode 2 — 13 September 2026, live on the track

| | |
| --- | --- |
| Version | `1.0.0+2` — bumped in the working tree, never committed |
| Built from | commit `3bc2118` plus that uncommitted bump |
| Artifact | 113 MB AAB |
| On the track | this is the build testers are running |

How the number was established, because it cost a round of the upload: the
committed `pubspec.yaml` at `3bc2118` says `1.0.0+1`, and an earlier version of
this file recorded the track as versionCode 1 on that basis. It was wrong. The
AAB built that day was built from a tree that had already been bumped to `+2`,
Play said so plainly when a bundle numbered 2 was offered —
"Version code 2 has already been used" — and build 3 exists because of it.

Everything before `3bc2118` is in this build, which means nothing from
19 September onward is: the version testers have is a week behind the app.

## The closed-testing clock

Play's requirement for a new personal developer account is at least **12 testers
opted in continuously for the preceding 14 days** at the moment production access
is applied for. What matters for the clock is that the track stays live and the
testers stay opted in — uploading a new build does not reset it, and testers
uninstalling does.

With 13 September as day 1: **20 September is day 8, and day 14 is 26
September.** The Play Console's own page is the authority on where that stands.

## Before build 3 goes up

- [ ] **Answer the foreground service declaration.** App content → Foreground
      service permissions. It is app-level and answered once; no rebuild and no
      new `versionCode` is involved. The merged release manifest declares exactly
      one type and one permission — `foregroundServiceType="dataSync"` with
      `FOREGROUND_SERVICE_DATA_SYNC`.

      Under **Data sync**, select **Local processing → Importing, exporting**.
      That is the documented use case rather than a stretch: Android lists
      "Import or export operations" and "Local file processing" as `dataSync`
      work, and the service exists to write the converted copy. Do **not** select
      *Media transcoding* — that wording belongs to
      `FOREGROUND_SERVICE_MEDIA_PROCESSING`, which is Android 15+ only, so
      choosing it under `dataSync` is the answer most likely to come back as a
      type mismatch.

      The free-text answers used:

      > OneKit converts files the user selects, entirely on the device. When the
      > user taps Convert, the app starts a data-sync foreground service so a
      > long run — a large video, or a batch the user queued — is not killed when
      > they switch apps or lock the screen. The service performs no network
      > transfer: it writes the converted file to the app's own storage and then
      > copies it to Downloads or the device Gallery through MediaStore. A single
      > ongoing notification names the file being processed, shows progress and
      > offers Cancel; when the run ends, the notification is replaced by a short
      > "converted, 12% smaller" message.
      >
      > If the task is deferred: nothing defers it. The service starts only from
      > the user's own tap on Convert, in the foreground, and work begins
      > immediately; a delayed start would only leave the app's own progress
      > display sitting still, and nothing is written until conversion completes.
      >
      > If the task is interrupted: the conversion stops where it is, the partial
      > temporary file is discarded, and the queue shows the job as stopped rather
      > than finished. The original file is never modified and the ongoing
      > notification goes with the service, so the user is never left with a
      > progress bar that lies.

      The declaration also wants a **video link** per type, and it is mandatory —
      the form will not save without it, and it is reviewed, so a placeholder or
      an unrelated link gets the declaration refused and leaves the release
      blocked. Unlisted on YouTube, not private.

      What the recording has to show, in order — the trigger steps the user takes
      and the fact that the work continues while they are not in the app:

      1. Open OneKit and pick a file (or a folder), then tap **Convert**.
      2. Allow the notification permission when it asks — refuse it and there is
         nothing on screen to demonstrate.
      3. Press **Home** so the app leaves the screen immediately, then pull down
         the shade and show the ongoing notification naming the file with a
         progress figure and a **Cancel** action.
      4. Leave it there long enough for the progress to visibly change — this is
         the whole point, so use a large video or a batch of files, not a
         thumbnail that finishes before you can open the shade.
      5. Tap the notification back into the app, then let the run finish and show
         the **completion** notification replacing the progress one.

      Screen-record it with Android's built-in recorder (Quick Settings → Screen
      record), 45–90 seconds, unedited, no narration required. The steps should
      match the description above word for word — the description promises a
      progress figure, a Cancel action and a completion message, so all three
      need to appear.

      Getting build 3 onto the phone for this: the declaration blocks *uploads*,
      so Play cannot deliver it yet. Build a release APK from this same tree
      (`flutter build apk --release --split-per-abi`) and `adb install -r` it, or
      try Internal app sharing (Test and release → Setup → Internal app sharing),
      which is a separate upload path from the tracks and may not hit the same
      gate. That install is also the device pass build 3 needs — one trip, both
      purposes.

      If it is refused, the fallbacks are `mediaProcessing` (a literal match for
      "converting media to different formats", but Android 15+ only, so both
      types would be declared and chosen at runtime) and `shortService` (no FGS
      permission at all, therefore nothing to declare, but hard-capped near three
      minutes so it suits only short conversions).
- [ ] **Run build 3 on a phone.** Started 20 September on the Moto G06 Power
      (Android 15, API 35, arm64): `versionCode=3` is installed, the app launches,
      and `libflutter.so` loads clean.

      Installing it required removing the Play build first, and that will be true
      on any phone carrying the closed-test build: Play re-signs what it delivers
      with its **app-signing key**, so an APK built locally (upload key) cannot
      replace it — `adb install -r` fails with
      `INSTALL_FAILED_UPDATE_INCOMPATIBLE: signatures do not match`. The way in is
      `adb uninstall com.onekit.converter` followed by `adb install` of
      `flutter build apk --release --target-platform android-arm64` (81,296,883
      bytes). Two consequences: the app's own data on that phone is gone (files
      already written to Downloads or the Gallery are not), and Play stops
      updating it until it is uninstalled again and reinstalled from the track.

      It is the first release build with R8 over the new service and three
      channels, and the first with `POST_NOTIFICATIONS` and
      `FOREGROUND_SERVICE_DATA_SYNC` in it. Worth exercising: pick a whole
      folder, watch the notification appear while the run goes and land after it,
      find the result in Gallery or `Download/OneKit`, and go back to Auto for
      bitrate, sample rate, video quality and frame rate. A release-only failure
      has bitten this app before — `49fc891`, "Fix a release-only isolate failure
      that broke every Dart image conversion".
- [ ] **Write the track release notes** from the commit list above, naming what
      to test, so the feedback that comes back is attributable to a build.
- [ ] **Recapture the screenshots** listed in `listing.md` — three of the seven
      predate the UI the listing now describes.
- [ ] **Delete the superseded `LocalFileConverter-1.0.0+2.aab`** from the
      Desktop once build 3 is on the track; it cannot be uploaded now, and the
      code in it is the same code the track already has.
