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

Re-verified from the artifact's own bytes on 3 October 2026: the Desktop upload
copy `~/Desktop/app-release.aab` is still 119,532,684 bytes and hashes to
`07d1da83c784fb934142220a7e85423ae4129964ca8ab4683292d2f3df563759`, it carries
`com.onekit.converter` with `versionCode 4`, and its `versionName` is `1.1.0` —
the record below stands unchanged; nothing was rebuilt.

Production access was granted on 2 October, so this is the first build that
can go to production rather than to the closed test. What it changes:

| | |
| --- | --- |
| Version | `1.1.0+4` (versionName 1.1.0, versionCode 4) |
| Built from | commit `494c8a4` and the `+4` bump in the commit before it |
| Artifact | `app-release.aab`, 119,532,684 bytes (114.0 MB) |
| SHA-256 | `07d1da83c784fb934142220a7e85423ae4129964ca8ab4683292d2f3df563759` |
| Signed | upload key `CN=OneKit`, serial `e97afa60114d2212`, SHA-256 `71:7A:44:F8:…:7E:14:9A`, valid to 19 August 2056 |
| Copy for upload | `~/Desktop/app-release.aab` |
| Build output | `build/app/outputs/bundle/release/app-release.aab` (git-ignored) |
| Device pass | `app-release.apk`, 81,816,702 bytes, SHA-256 `a237dd223f165c90a6bc73e70e4ed1237640d392912ba6d6e376987132b68d42` |

The `versionCode` inside the bundle was read back out of it, not assumed:
`tool/release_check.dart` reports `versionCode is 4 (found 4)` from
`base/manifest/AndroidManifest.xml`, and the APK is read the same way through
the SDK's own `aapt2 dump badging`. The same tool is what caught build 3's
missing ad units, and it is run against every artifact before it is copied
anywhere — thirteen checks, all read from the file rather than from the tree.

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

#### The device pass, 2 October

The release APK was installed on the Moto G06 Power (`ZA223CF3NX`, Android 15)
over `adb uninstall` of the Play build, and walked screen by screen:

| Check | Result |
| --- | --- |
| Version on device | `versionCode=4`, `versionName=1.1.0` |
| Demo units in the installed binary | none — production account ×5, sample account ×0, read out of `libapp.so` |
| New icon | installed `res/BW.xml` is the adaptive icon with the new background, the 16%-inset foreground and monochrome; the background and monochrome PNGs are **pixel-identical** to the generated art, the foreground differs on 0.24% of pixels (aapt2 re-encoding, not different art) |
| Banner on every screen | filled on all five tabs plus PDF tools, About and the report screen |
| Native ad row | filled in both History and Files |
| A conversion, with ads on | JPG → PNG, 747 ms, result listed in Files, no ad over the run |
| Interstitial | appeared after the third finished run and dismissed back to the app |
| Settings rows | "Hide ads for an hour" present; the privacy-options row correctly absent while no consent form exists |

Two things this pass turned up that no test would have:

- **The interstitial cadence is correct but was not obvious.** It counts runs
  within a session, so the ad lands on the third run of a launch, not the third
  ever. The first probe saw nothing because an earlier session had already spent
  the count.
- **App-open and rewarded both fail to load, with `Ad unit doesn't match
  format`.** The same two units that failed during the first device attempt, and
  they failed again on a connection that resolved DNS and served a real
  advertiser in the banner and the native slot — so it is not the network. The
  other three units of the same account serve fine, which points at the two
  unit IDs themselves rather than at the code: the IDs went in on 13 September
  (`0075097`) and have never been checked against the console. Both are
  preloaded and neither is on a critical path, so the effect today is that a
  launch shows no app-open ad and "Hide ads for an hour" answers "No video was
  ready just now" — visible, but not broken. Worth confirming each ID in AdMob
  against its format before build 5.

### Build 6 — versionCode 6 — 8 October 2026, the cold launch finally gets its ad

| | |
| --- | --- |
| Version | `1.1.0+6` (versionName 1.1.0, versionCode 6) |
| Built from | the working tree of this pass — `lib/core/ads/ads.dart`, `lib/core/ads/ad_policy.dart`, two new tests in `test/ad_policy_test.dart` and the `+6` bump, **not yet committed** when the bundle was built (committed 8 Oct 2026 as `19ff086`); build 5's own changes are in the same tree |
| Artifact | `LocalFileConverter-1.1.0+6.aab`, 119,535,272 bytes (114.0 MB) |
| SHA-256 | `58bf8945434e4e8e91659ff32d7cc7c0aa74cf2ab5048ab48d292bed35b62c02` |
| Signed | upload key `CN=OneKit`, serial `e97afa60114d2212`, SHA-256 `71:7A:44:F8:…:7E:14:9A` — the same key as every build |
| Copy for upload | `~/Desktop/LocalFileConverter-1.1.0+6.aab`; build 5's copies are left where they are |
| Build output | `build/app/outputs/bundle/release/app-release.aab` (git-ignored) |
| Device pass | `LocalFileConverter-1.1.0+6.apk`, 94,081,698 bytes, SHA-256 `6e17572353bf17d6e9c58d826c15558ac832e422252bb57abbb70bcf4351a929` |

**The one change: a cold launch now waits for the ad it asked for.** Build 5's
record named the defect — `showAppOpenOnLaunch()` showed only an ad that was
already in hand, and at a cold launch the request has just gone out, so the
launch always found nothing and the ad it had fetched was spent on the next
return. This fixes that shape rather than the symptom, the same shape ComingUp
1.0.12+14 uses:

- `_preloadAppOpen()` keeps the request it has in flight, `_appOpenRequest`,
  which the load callbacks resolve with the ad or with null. The launch path
  therefore has something to wait for instead of something to look for.
- `showAppOpenOnLaunch()` waits for that answer inside
  `AdPolicy.appOpenShowWindow` (five seconds — a new constant, with its reason)
  and then **re-checks the rules** before showing: the SDK being up, the hour,
  and the launch cooldown itself, so a reward bought or a return that showed an
  ad while this one was in flight cannot produce a second one.
- `_appOpenWithin(window)` hands back what is in hand *without consuming it*: an
  ad the rules no longer allow stays in hand for the next return rather than
  being thrown away, and only an ad that is still the manager's own is handed
  back, so a stale object can never be shown.

Nothing else changed. The rewarded unit is still `/6329394147` and still answers
`Ad unit doesn't match format` — that is the other half of build 4's finding and
it needs a Rewarded unit created in the console, not a code change.

#### The device pass, 8 October

Installed over the 1.1.0+5 install with `adb install -r` — the same signing key
and a higher version code, so it was an update and the app's own data was
preserved.

| Check | Result |
| --- | --- |
| Version on device | `versionCode=6`, `versionName=1.1.0` |
| Units in the installed binary | production account ×5 including `/9898941203`, the old `/9684466592` absent, sample account ×0, read out of `libapp.so` in both ABIs |
| The bundle | `dart run tool/release_check.dart` against the AAB: **13 checks, 0 failing** |
| The manifest | `aapt2` reads `versionCode 6`, `versionName 1.1.0` and the app id `ca-app-pub-2489505475567649~2600183490` |
| **App-open on a cold launch** | **served** — force-stopped, launched, and the focused window became `com.onekit.converter/com.google.android.gms.ads.AdActivity` about 4–5 s later, captured in `_phone_1.1.0_build6_appopen_launch.png` and `_phone_1.1.0_build6_appopen_showing.png` |
| Dismissing it | the first Back did not close it — the SDK holds an app-open ad until its own close is offered — and a Back about 100 s in returned focus to `com.onekit.onekit_converter.MainActivity`, with the same process (pid 12016) still up and the app redrawn (`_phone_1.1.0_build6_after_appopen.png`) |
| The app's own log | no app-open load error at all this launch: the unit answered, and this time the launch showed it |
| Consent | still `Publisher misconfiguration: … no form(s) configured for the input app ID` — the missing GDPR/US-states message, owner-side (M8's checklist) |
| Reward video | still `Ad unit doesn't match format` — unchanged from builds 4 and 5 |

Gates: `flutter analyze` clean, **229 app tests** (+2 — the launch window's
size, and the rule that a launch which found no ad spends no cooldown, so the
next return is still due), and the release check 13/13. The launch decision
itself stays where the other ad rules are: the window is `AdPolicy`'s, and the
manager only ever asks it.

Still open, unchanged by this pass: the rewarded unit, the consent message and
the Play upload.

### Build 5 — versionCode 5 — 8 October 2026, the app-open unit the owner supplied

| | |
| --- | --- |
| Version | `1.1.0+5` (versionName 1.1.0, versionCode 5) |
| Built from | the working tree of this pass — `lib/core/ads/ad_ids.dart`, `tool/release_check.dart` and the `+5` bump, **not yet committed** when the bundle was built (committed 8 Oct 2026 as `19ff086`) |
| Artifact | `LocalFileConverter-1.1.0+5.aab`, 119,532,881 bytes (114.0 MB) |
| SHA-256 | `27811dd91cc094dd71077bcf869c4480ac9b90a10a433174df3a9e1315b8183a` |
| Signed | upload key `CN=OneKit`, serial `e97afa60114d2212`, SHA-256 `71:7A:44:F8:…:7E:14:9A`, valid to 19 August 2056 — the same key as every build |
| Copy for upload | `~/Desktop/LocalFileConverter-1.1.0+5.aab`; build 4's `app-release.aab` is left where it was, untouched |
| Build output | `build/app/outputs/bundle/release/app-release.aab` (git-ignored) |
| Device pass | `LocalFileConverter-1.1.0+5.apk`, 94,080,554 bytes, SHA-256 `3ddb1284487cbf41d4e72d9b38abd7a2fda04b9b5ae3c445090ad1cfbd794338` |

**One change: the app-open unit.** Build 4's device pass ended with "worth
confirming each ID in AdMob against its format before build 5", and the answer
was the format: `/9684466592` was not an app-open unit, which is why every
request to it came back as `Ad unit doesn't match format`. The owner supplied a
new one on 8 October 2026 and it replaces the old id in `AdIds._production`:

| | |
| --- | --- |
| Was | `ca-app-pub-2489505475567649/9684466592` |
| Now | `ca-app-pub-2489505475567649/9898941203` |

Nothing else changed. `tool/release_check.dart` looks for the new value, so an
artifact built from the old tree fails that check by name; the demo table still
holds Google's app-open sample (`/9257395921`), and a debug build is still the
only build that asks for it.

#### The device pass, 8 October

Installed over the 1.1.0+4 install with `adb install -r` — the same signing key
and a higher version code, so it was an update and the app's own data was
preserved.

| Check | Result |
| --- | --- |
| Version on device | `versionCode=5`, `versionName=1.1.0` |
| Units in the installed binary | production account ×5 including `/9898941203`, the old `/9684466592` absent, sample account ×0, read out of `libapp.so` |
| The bundle | `dart run tool/release_check.dart` against the AAB: **13 checks, 0 failing** |
| App-open on a cold launch | **did not appear** — see below |
| App-open on a return | **served**, after 150 s away: the focused window became `com.onekit.converter/com.google.android.gms.ads.AdActivity`, captured in `_phone_1.1.0_build5_appopen_resume.png` |
| Dismissing it | Back returned focus to `com.onekit.onekit_converter.MainActivity`, the process stayed up and the app redrew (`_phone_1.1.0_build5_after_appopen.png`) |
| Reward video | still `Ad unit doesn't match format` — `/6329394147` is the second of the two bad ids and was not replaced this pass |

Two things this pass turned up:

- **The cold-launch app-open cannot show, and it is the code rather than the
  unit.** `showAppOpenOnLaunch()` runs after the first frame and `_showAppOpen()`
  shows only an ad that is *already* in hand; the preload started moments earlier
  in `initialize()` cannot have finished, so a cold launch always finds nothing,
  calls `_preloadAppOpen()` again, and the ad those requests fetch sits in
  `_appOpen` until the next return — which is exactly what the resume probe saw.
  Showing an app-open ad when it arrives, while the launch window is still open,
  is the standard shape for the format (and what ComingUp 1.0.12+14 does), so the
  fix is to let the load completion show it.
- **The rewarded unit is the other half of build 4's finding and is still
  broken.** `/6329394147` answers with the same format error. It needs what the
  app-open unit just got: a Rewarded unit created or confirmed in the console,
  then swapped in, with `tool/release_check.dart` moved with it.

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
