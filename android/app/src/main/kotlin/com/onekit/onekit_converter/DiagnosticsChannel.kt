package com.onekit.onekit_converter

import android.app.ActivityManager
import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import android.os.StatFs
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * What this device and this build are, for a failure report.
 *
 * A closed test produces reports that all look alike — "it didn't work" — and
 * the difference between a real bug and an ARM-only APK on an unusual phone is
 * usually one of these fields. Everything here is readable without a single
 * permission, which is deliberate: the app's privacy claim is that it asks for
 * nothing, and a diagnostics feature is exactly the kind of thing that would
 * quietly break it.
 *
 * Only facts are returned, not sentences. The wording lives in Dart, where it
 * is visible in the report preview the user reads before sending anything.
 */
object DiagnosticsChannel {

    private const val CHANNEL = "onekit/diagnostics"

    fun attach(context: Context, messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "environment" -> result.success(environment(context))
                else -> result.notImplemented()
            }
        }
    }

    private fun environment(context: Context): Map<String, Any?> {
        val out = linkedMapOf<String, Any?>()
        val manager = context.packageManager

        out["packageName"] = context.packageName
        // Deprecated on API 33 in favour of the flag-taking overload, but it
        // still returns the same two fields on every version this app ships to,
        // and one call that works everywhere beats a version check.
        @Suppress("DEPRECATION")
        val info = try {
            manager.getPackageInfo(context.packageName, 0)
        } catch (e: Exception) {
            null
        }
        if (info != null) {
            out["versionName"] = info.versionName
            out["versionCode"] = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                info.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                info.versionCode.toLong()
            }
        }

        // Where the build came from: a Play install and a hand-installed test
        // APK fail in different ways, and this is the only field that says which
        // one the report is about.
        out["installer"] = installer(manager, context.packageName)

        out["manufacturer"] = Build.MANUFACTURER
        out["brand"] = Build.BRAND
        out["model"] = Build.MODEL
        out["device"] = Build.DEVICE
        out["androidRelease"] = Build.VERSION.RELEASE
        out["sdkInt"] = Build.VERSION.SDK_INT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            out["securityPatch"] = Build.VERSION.SECURITY_PATCH
        }
        out["abis"] = Build.SUPPORTED_ABIS.joinToString(", ")
        out["nativeAbi"] = installedAbi(context)
        out["buildType"] = Build.TYPE
        out["emulator"] = isEmulator()
        out["debuggable"] =
            (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0

        val activityManager =
            context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
        if (activityManager != null) {
            val memory = ActivityManager.MemoryInfo()
            activityManager.getMemoryInfo(memory)
            out["totalRamMb"] = memory.totalMem / (1024 * 1024)
            out["lowRam"] = activityManager.isLowRamDevice
        }

        // Free space on the app's own volume. A full phone is one of the few
        // failures the user can fix themselves, and it leaves no other trace.
        try {
            val stat = StatFs(context.filesDir.absolutePath)
            out["freeStorageMb"] = stat.availableBytes / (1024 * 1024)
            out["totalStorageMb"] = stat.totalBytes / (1024 * 1024)
        } catch (e: Exception) {
            // Not worth reporting the absence of.
        }

        return out
    }

    private fun installer(manager: PackageManager, packageName: String): String? {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                manager.getInstallSourceInfo(packageName).installingPackageName
            } else {
                @Suppress("DEPRECATION")
                manager.getInstallerPackageName(packageName)
            }
        } catch (e: Exception) {
            null
        }
    }

    /**
     * The ABI of the APK that is actually installed, taken from the directory
     * the native libraries were unpacked into. A device lists every ABI it can
     * run; this says which one the build in question is using, which is what
     * decides whether an `UnsatisfiedLinkError` is even possible.
     */
    private fun installedAbi(context: Context): String? {
        val dir = context.applicationInfo.nativeLibraryDir ?: return null
        return dir.substringAfterLast('/').takeIf { it.isNotEmpty() }
    }

    /**
     * The usual fingerprint test. Emulator reports are worth knowing about
     * because they explain a whole class of failures — no hardware decoder —
     * without anyone having to ask.
     */
    private fun isEmulator(): Boolean {
        val fingerprint = Build.FINGERPRINT.lowercase()
        val model = Build.MODEL.lowercase()
        val product = Build.PRODUCT.lowercase()
        val hardware = Build.HARDWARE.lowercase()
        return fingerprint.startsWith("generic") ||
            fingerprint.contains("emulator") ||
            fingerprint.contains("vbox") ||
            model.contains("google_sdk") ||
            model.contains("emulator") ||
            model.contains("android sdk built for") ||
            Build.MANUFACTURER.contains("Genymotion") ||
            hardware.contains("goldfish") ||
            hardware.contains("ranchu") ||
            product.contains("sdk")
    }
}
