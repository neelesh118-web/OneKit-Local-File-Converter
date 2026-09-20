package com.onekit.onekit_converter

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import kotlin.math.roundToInt

/**
 * Keeps a conversion running while the app is not on screen, and says so.
 *
 * The conversion itself happens on the Dart side, in this process; what Android
 * needs before it will leave that process alone is a foreground service with a
 * notification attached. Without one a long video, a batch, or a hundred-page
 * PDF render is a background app waiting to be killed, which is the "it just
 * stopped" a tester reports after switching apps.
 *
 * The service holds nothing and converts nothing. It exists to be alive: the
 * notification is the price of that, so it is written to be worth reading —
 * what is running, how far along, and then what came out.
 *
 * The two channel names and descriptions below are the only user-facing words
 * in the Kotlin half, and they have to be: a channel has to exist before the
 * first notification can be posted, and the system reads its name from here
 * rather than from Dart. Everything else on screen is worded in Dart.
 */
class ConversionService : Service() {

    companion object {
        /** A run in progress. Silent: a job being worked on is not an event. */
        private const val CHANNEL_PROGRESS = "conversion_progress"

        /** The finished one may make a sound. It is often the only signal that a
         *  run started while the user was in another app has ended. */
        private const val CHANNEL_DONE = "conversion_done"

        private const val PROGRESS_ID = 7411
        private const val DONE_ID = 7412

        /**
         * Whether the service is up and holding this process.
         *
         * Progress reports are dropped while it is not. A notification posted to
         * the id no service is holding would be one the user cannot dismiss, and
         * it would outlive the run that posted it: a notification lives as long
         * as the process that posted it, and the service is what ties that
         * process to the run.
         */
        @Volatile
        private var live = false

        /** Channels are created once per process. */
        @Volatile
        private var channelsReady = false

        private const val ACTION_BEGIN = "com.onekit.onekit_converter.action.BEGIN"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_TEXT = "text"
        private const val EXTRA_FRACTION = "fraction"

        /** Raises the process to foreground, or refreshes it if already there. */
        fun begin(context: Context, title: String, text: String, fraction: Double?) {
            channels(context)
            // ContextCompat rather than Context: startForegroundService arrived
            // in Android 8, and this app still runs on 7.
            ContextCompat.startForegroundService(
                context,
                Intent(context, ConversionService::class.java)
                    .setAction(ACTION_BEGIN)
                    .putExtra(EXTRA_TITLE, title)
                    .putExtra(EXTRA_TEXT, text)
                    .putExtra(EXTRA_FRACTION, fraction ?: -1.0),
            )
        }

        /**
         * Updates the notification in place.
         *
         * Posted directly rather than sent through the service: it is the same
         * notification id, so it lands on the foreground notification while the
         * service is up, and there is nothing for the service to do about it.
         */
        fun report(context: Context, title: String, text: String, fraction: Double?) {
            if (!live) return
            channels(context)
            post(context, PROGRESS_ID, progress(context, title, text, fraction))
        }

        /** Ends the run, leaving [notice] behind when there is one. */
        fun end(context: Context, notice: String?) {
            // Before the service is asked to stop, which it does asynchronously:
            // a report arriving in that gap is for a run that is over.
            live = false
            context.stopService(Intent(context, ConversionService::class.java))
            val manager = NotificationManagerCompat.from(context)
            // The service's own notification goes away with it. This also covers
            // the case where a report posted one and the service never started.
            manager.cancel(PROGRESS_ID)
            if (notice != null) {
                channels(context)
                post(context, DONE_ID, done(context, notice))
            }
        }

        /**
         * Posts a notification, unless the user has not allowed them.
         *
         * From Android 13 that allowance is a permission, and this is the one
         * place that has to take no for an answer: the app can only ask, and a
         * refusal costs the notification rather than the conversion. Below
         * Android 13 there is nothing to refuse and nothing to check.
         */
        private fun post(context: Context, id: Int, notification: Notification) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED
            ) {
                return
            }
            try {
                NotificationManagerCompat.from(context).notify(id, notification)
            } catch (e: SecurityException) {
                // Refused in the moment between the check and the post. There is
                // nothing to do about it and nothing worth interrupting a
                // conversion for.
            }
        }

        private fun progress(
            context: Context,
            title: String,
            text: String,
            fraction: Double?,
        ): Notification {
            val builder = NotificationCompat.Builder(context, CHANNEL_PROGRESS)
                // A monochrome launcher icon: the system masks a small icon to a
                // silhouette anyway, and the app already ships one.
                .setSmallIcon(R.drawable.ic_launcher_monochrome)
                .setContentTitle(title)
                .setContentText(text)
                .setContentIntent(openApp(context))
                .setOngoing(true)
                .setSilent(true)
                // Several updates land on one notification, and only the first
                // may make a sound.
                .setOnlyAlertOnce(true)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setCategory(NotificationCompat.CATEGORY_PROGRESS)

            if (fraction == null) {
                builder.setProgress(0, 0, true)
            } else {
                builder.setProgress(100, (fraction * 100).roundToInt().coerceIn(0, 100), false)
            }
            return builder.build()
        }

        private fun done(context: Context, notice: String): Notification =
            NotificationCompat.Builder(context, CHANNEL_DONE)
                .setSmallIcon(R.drawable.ic_launcher_monochrome)
                .setContentTitle(notice)
                .setContentIntent(openApp(context))
                .setAutoCancel(true)
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                .build()

        /** Tapping either notification brings the app back to the front. */
        private fun openApp(context: Context): PendingIntent = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        private fun channels(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            // Asked for on every progress report, and creating a channel that
            // already exists is a binder round-trip to the system for nothing.
            if (channelsReady) return
            val manager = context.getSystemService(NotificationManager::class.java) ?: return
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_PROGRESS,
                    "Conversions in progress",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Shows how far along a running conversion is."
                    setShowBadge(false)
                },
            )
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_DONE,
                    "Finished conversions",
                    NotificationManager.IMPORTANCE_DEFAULT,
                ).apply {
                    description = "Says when a conversion has finished."
                },
            )
            channelsReady = true
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra(EXTRA_TITLE)
        if (title == null) {
            // Started without a run to describe, which only happens if the
            // system restarted it. There is nothing to report, and the platform
            // will not wait: a service started this way has seconds to call
            // startForeground or be killed for not doing it.
            stopSelf()
            return START_NOT_STICKY
        }

        val text = intent.getStringExtra(EXTRA_TEXT).orEmpty()
        val fraction = intent.getDoubleExtra(EXTRA_FRACTION, -1.0).takeIf { it >= 0.0 }
        startForeground(PROGRESS_ID, progress(this, title, text, fraction))
        live = true

        // Never restarted on its own. A run belongs to the Dart side, and a
        // service left running after Dart has gone would be a notification with
        // nothing behind it.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        live = false
        super.onDestroy()
    }

    /**
     * The platform's own ceiling on a `dataSync` service.
     *
     * From Android 15 an app may run `dataSync` services for six hours in any
     * twenty-four, and is given a few seconds' warning when that is spent.
     * Stopping here is what keeps the warning from becoming a crash — an app
     * that ignores it is killed with `ForegroundServiceDidNotStopInTimeException`
     * — and it costs the run nothing that matters: the work continues as an
     * ordinary background app, which is all it was before the service existed.
     * Only the notification ends.
     */
    override fun onTimeout(startId: Int, fgsType: Int) {
        stopSelf()
    }
}
