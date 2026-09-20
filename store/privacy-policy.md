# Privacy Policy — 100% Local File Converter

**Last updated: 27 August 2026**

## The short version

This app converts your files on your phone. Your files are never uploaded,
never sent to a server, and never seen by anyone but you. There is no account
and no sign-in.

The only part of this app that uses the internet at all is the advertising
banner, provided by Google AdMob.

## What the app does with your files

When you pick a file, the app reads it, converts it on your device, and writes
the result into its own private storage folder. So that a converted file is
findable outside the app, a copy is also placed in your phone's own Gallery —
or in **Download/OneKit** for documents and other files a gallery would not
show — where your other apps can see it. Both copies are on your device:
nothing is uploaded, and neither is shared with us or anyone else.
**Settings → Save to Gallery** turns the copy off; with it off, results stay
inside the app's private folder and leave only through a share sheet you
choose.

Files you hand to the app — shared in from another app, or read out of a folder
you pick — are first copied into that same working storage, because the
converters work on files rather than on Android's `content://` addresses.
**Settings → Clear working files** erases those copies and everything else the
app kept while working.

- Your files are **not uploaded** anywhere.
- Your files are **not shared** with us or any third party.
- We **cannot see** your files, their names, or their contents. There is no
  server for them to reach.
- Conversion works with no internet connection at all.

The list of conversions you have run ("History") and your settings are stored
in private storage on your device. They are not transmitted. You can erase
them at any time from **Settings → Clear conversion history** and
**Settings → Clear working files**, or by uninstalling the app.

## What is collected

The app itself collects nothing.

The app displays ads through **Google AdMob**. To show those ads, Google may
collect and process:

- your device's **advertising ID**,
- general device information (model, operating system version, language),
- coarse location inferred from your IP address,
- ad interaction data (whether an ad was shown, viewed, or tapped).

This is handled by Google, not by us, and is governed by Google's own privacy
policy: <https://policies.google.com/privacy>

You can limit this at any time in **Android Settings → Privacy → Ads**, where
you can delete or reset your advertising ID and opt out of ad personalisation.

## Permissions the app requests, and why

| Permission | Why |
| --- | --- |
| `INTERNET` | Required to load ads. Nothing else in the app uses the network. |
| `ACCESS_NETWORK_STATE` | Required by the Google Mobile Ads SDK. |
| `AD_ID` | Required by AdMob on Android 13 and above. |
| `WAKE_LOCK` | Keeps long video and batch conversions running while the app is open. |
| `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC` | Let a running conversion continue when you switch to another app instead of being killed in the background. |
| `POST_NOTIFICATIONS` | Shows that run's progress, and says when it has finished. Asked for when the first conversion starts; declining it costs only the notification, and the conversion still runs. |

The app does **not** request storage permission. Files reach the app only
through Android's own pickers — one file at a time, or a single folder you lend
the app through the system's folder picker, which grants access to that one
folder and nothing else — so you choose explicitly what it may read, and results
are shared out through Android's share sheet. The Gallery copy uses Android's
own media store, which needs no permission on Android 10 and above; on older
versions it is not written, and the result stays in the app's private folder.

## Diagnostics and reports

The app has no analytics, no crash-reporting SDK, and no endpoint to send
anything to. If a conversion fails, the result screen offers **Send a report**.
The app then writes a plain-text report containing what you typed, the device
model, the Android version and security patch, the ABI the installed build is
running, the app version and build number, where the build was installed from,
the conversion options, and the engine's own output for the failure — FFmpeg's
log tail or the decoder's message. The whole text is shown on screen before you
send it, and it leaves the device only through a share sheet you choose, to a
recipient you pick.

The report contains no file contents, and the folder paths an error message
mentions are trimmed back to the file name. The names of the files involved are
included, because a failure cannot be identified without them.

## Children

The app is a general-purpose utility and is not directed at children. We do not
knowingly collect personal information from anyone.

## Payments and donations

The app is free. If you choose to leave a tip, that link opens Buy Me a Coffee
in your browser. Any payment happens entirely on their site under their own
privacy policy; the app neither sees nor stores payment details.

## Changes to this policy

If this policy changes, the revised version will be published at this same
address with an updated date above.

## Contact

Questions about this policy: **neeleshasati118@gmail.com**
