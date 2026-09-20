# Releases

Which artifact is on which track, what is in it, and which commit it came from.
The `versionCode` is what Play keys on and it comes from `pubspec.yaml`, so it is
worth writing down beside the commit — otherwise a build on a track cannot be
traced back to the code that produced it.

The AAB itself is deliberately **not** in this repository: it is over a hundred
megabytes of something git cannot diff, and `build/` is ignored for that reason.
The path below is where the copy for upload lives.

## Closed testing

### Build 2 — versionCode 2 — built 20 September 2026, not yet uploaded

| | |
| --- | --- |
| Version | `1.0.0+2` (versionName 1.0.0, versionCode 2) |
| Built from | commit `2ff9286`, clean working tree |
| Artifact | `app-release.aab`, 118,785,562 bytes (113.3 MB) |
| sha256 | `1f9b4c8be29d3b1e968dabacc5e91dbe3c986b86b21775f6abcbcfccdd98dd24` |
| Signed | upload key `CN=OneKit`, valid to 19 August 2056 |
| Copy for upload | `~/Desktop/LocalFileConverter-1.0.0+2.aab` |
| Build output | `build/app/outputs/bundle/release/app-release.aab` (git-ignored) |

Nine commits past build 1, which is everything a tester has not seen:

- Optimize, the PDF toolbox, share-in, presets and failure reports (`efd0592`,
  `507a01a`, `9ea61d2`, `eeabd7e`, `bc60e4a`)
- Batch optimize, and the docs for all six (`130de66`, `1bb879c`)
- Even dimensions for animated image targets (`48fd8e6`)
- Gallery copies, background runs and notifications, whole-folder picking, the
  options sheet's Auto fix, and four audit fixes (`2ff9286`)

### Build 1 — versionCode 1 — 13 September 2026, live on the track

| | |
| --- | --- |
| Version | `1.0.0+1` (versionName 1.0.0, versionCode 1) |
| Built from | commit `3bc2118` — "Bump targetSdk to 36 for Play Store requirement" |
| Artifact | 113 MB AAB |
| On the track | uploaded for closed testing; this is the build testers are running |

Everything before `3bc2118` is in this build, which means nothing from 19
September onward is: the version testers have is a week behind the app.

## The closed-testing clock

Play's requirement for a new personal developer account is at least **12 testers
opted in continuously for the preceding 14 days** at the moment production access
is applied for. What matters for the clock is that the track stays live and the
testers stay opted in — uploading a new build does not reset it, and testers
uninstalling does.

With 13 September as day 1: **20 September is day 8, and day 14 is 26
September.** The Play Console's own page is the authority on where that stands.

## Before build 2 goes up

- [ ] **Answer the foreground service declaration.** App content → Foreground
      service permissions. The app targets API 36 and declares
      `FOREGROUND_SERVICE_DATA_SYNC` with `foregroundServiceType="dataSync"`, so
      Play will not publish the release until this is declared. The true
      description: a conversion the user started keeps running when the app
      leaves the screen, with a visible, cancellable progress notification, and
      it writes the user's own converted file. If a reviewer objects that a
      purely local conversion is not `dataSync`, the fallback is `specialUse`
      with a justification.
- [ ] **Run build 2 on a phone.** It is the first release build with R8 over the
      new service and three channels, and the first with `POST_NOTIFICATIONS` and
      `FOREGROUND_SERVICE_DATA_SYNC` in it. Worth exercising: pick a whole
      folder, watch the notification appear while the run goes and land after it,
      find the result in Gallery or `Download/OneKit`, and go back to Auto for
      bitrate, sample rate, video quality and frame rate. A release-only failure
      has bitten this app before — `49fc891`, "Fix a release-only isolate failure
      that broke every Dart image conversion".
- [ ] **Write the track release notes** from the commit list above, naming what
      to test, so the feedback that comes back is attributable to a build.
- [ ] **Confirm the versionCode on the track is 1**, so 2 is free to use.
- [ ] **Recapture the screenshots** listed in `listing.md` — three of the seven
      predate the UI the listing now describes.
