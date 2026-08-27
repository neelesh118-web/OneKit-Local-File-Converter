# FFmpeg Kit and its native bridge are reached through JNI, so the class names
# must survive shrinking.
-keep class com.antonkarpenko.ffmpegkit.** { *; }
-keep class com.arthenica.** { *; }

# pdfrx talks to pdfium through FFI.
-keep class io.flutter.plugins.** { *; }

# Google Mobile Ads
-keep class com.google.android.gms.ads.** { *; }
-dontwarn com.google.android.gms.**

# Play Core is referenced by the Flutter deferred-components stubs but is not
# bundled; without this the release build fails on a missing class.
-dontwarn com.google.android.play.core.**

-dontwarn javax.annotation.**
-dontwarn org.slf4j.**
