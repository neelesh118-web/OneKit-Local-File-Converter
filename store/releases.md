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

### Build 3 — versionCode 3 — built 20 September 2026, not yet uploaded

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
      service permissions. The app targets API 36 and declares
      `FOREGROUND_SERVICE_DATA_SYNC` with `foregroundServiceType="dataSync"`, so
      Play will not publish the release until this is declared. The true
      description: a conversion the user started keeps running when the app
      leaves the screen, with a visible, cancellable progress notification, and
      it writes the user's own converted file. If a reviewer objects that a
      purely local conversion is not `dataSync`, the fallback is `specialUse`
      with a justification.
- [ ] **Run build 3 on a phone.** It is the first release build with R8 over the
      new service and three channels, and the first with `POST_NOTIFICATIONS` and
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
