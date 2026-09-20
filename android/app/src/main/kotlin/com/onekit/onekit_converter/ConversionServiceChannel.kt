package com.onekit.onekit_converter

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The Dart side of the conversion notification: start one for a run, keep its
 * progress up to date, and end it with whatever came out.
 *
 * Every call answers success, including the ones that did nothing. A conversion
 * must not fail because a notification could not be put up — a user who has
 * refused the notification permission still gets their files converted, they
 * just do not get told about it from another app.
 *
 * It is attached by the activity rather than the application context because
 * asking for the notification permission is something only an activity can do,
 * and the moment a run starts is when that request makes sense to the person
 * being asked.
 */
object ConversionServiceChannel {

    private const val CHANNEL = "onekit/background"

    /** Any small number: this app has one runtime permission request. */
    private const val REQUEST_NOTIFICATIONS = 7410

    fun attach(activity: Activity, messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "begin" -> begin(activity, call)
                    "report" -> report(activity, call)
                    "end" -> ConversionService.end(activity, call.argument<String>("notice"))
                    else -> {
                        result.notImplemented()
                        return@setMethodCallHandler
                    }
                }
                result.success(null)
            } catch (e: Exception) {
                // A notification that could not be shown, or a service the
                // platform would not let start from here. Neither is a reason to
                // interrupt the conversion that asked for it.
                result.success(null)
            }
        }
    }

    private fun begin(activity: Activity, call: MethodCall) {
        askForNotifications(activity)
        ConversionService.begin(
            activity,
            call.argument<String>("title") ?: return,
            call.argument<String>("text").orEmpty(),
            fraction(call),
        )
    }

    private fun report(activity: Activity, call: MethodCall) {
        val title = call.argument<String>("title") ?: return
        ConversionService.report(activity, title, call.argument<String>("text").orEmpty(), fraction(call))
    }

    /**
     * A missing fraction means the backend cannot measure itself; the platform
     * side draws a spinner for it. Anything else is a number out of 1.
     */
    private fun fraction(call: MethodCall): Double? =
        (call.argument<Number>("fraction"))?.toDouble()?.coerceIn(0.0, 1.0)

    /**
     * Android 13 and up hides every notification until the user allows them, so
     * the first conversion asks. Declining is a real answer and costs nothing:
     * the run continues, and the notification simply never appears.
     */
    private fun askForNotifications(activity: Activity) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val granted = ContextCompat.checkSelfPermission(activity, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        if (granted) return
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQUEST_NOTIFICATIONS,
        )
    }
}
