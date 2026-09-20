package com.onekit.onekit_converter

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * The activity that receives files other apps hand over.
 *
 * OneKit is a converter, so the files that arrive here are inputs: an image
 * from the Gallery's share sheet, a PDF from Files' "Open with", a handful of
 * videos shared at once. Android hands those over as `content://` URIs with a
 * temporary read grant, and this app's engines work on paths, so each one is
 * copied into the app's own scratch space before Dart is told about it. That
 * copy is why sharing needs no storage permission at all: the app only ever
 * reads the URI it was just handed, and writes inside its own cache.
 *
 * The copy runs off the main thread. A shared video can be hundreds of
 * megabytes, and blocking `onCreate` on that is an ANR.
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val METHOD_CHANNEL = "onekit/share"
        private const val EVENT_CHANNEL = "onekit/share_events"

        /**
         * Where shared files wait. Under `lfc_work` on purpose: that is the
         * directory `ConversionEngine.tempDir()` points at, so Settings' "Clear
         * working files" sweeps these up along with everything else, and nothing
         * is left behind that the user cannot clear.
         */
        private const val INBOX = "lfc_work/inbox"
    }

    private val main = Handler(Looper.getMainLooper())

    /** Non-null while Dart is listening for shares. */
    private var sink: EventChannel.EventSink? = null

    /** URIs from an intent dated before Dart was ready for them. */
    private val pending = mutableListOf<Uri>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Device and build facts for a failure report. Nothing else here needs
        // to know about them, so they live in their own file.
        DiagnosticsChannel.attach(applicationContext, flutterEngine.dartExecutor.binaryMessenger)

        // Handing a finished conversion to MediaStore so the phone's own apps
        // can see it. Its own file, for the same reason.
        MediaStoreChannel.attach(applicationContext, flutterEngine.dartExecutor.binaryMessenger)

        // The notification that keeps a conversion running while the app is off
        // screen. It takes the activity rather than the application context
        // because asking for the notification permission is the activity's job.
        ConversionServiceChannel.attach(this, flutterEngine.dartExecutor.binaryMessenger)

        // Converting a whole folder. Also takes the activity: the folder picker
        // is a screen it has to be launched from.
        FolderChannel.attach(this, flutterEngine.dartExecutor.binaryMessenger)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // The share that launched the app, if there was one.
                    "takeInitial" -> flushTo { files -> result.success(files) }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                        sink = events
                        // A share can arrive in the gap between the app launching
                        // and this listener attaching; deliver whatever is waiting.
                        flushTo(null)
                    }

                    override fun onCancel(arguments: Any?) {
                        sink = null
                    }
                },
            )
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        collect(intent)
    }

    /**
     * The folder picker's answer.
     *
     * Claimed here rather than by a plugin because this is the activity that
     * launched it; anything with another request code still goes to the
     * embedding, which is what every plugin here expects.
     */
    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (!FolderChannel.onActivityResult(this, requestCode, resultCode, data)) {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }

    /**
     * The activity is `singleTop`, so a share arriving while OneKit is already
     * open lands here rather than starting a second copy of the app.
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        collect(intent)
    }

    // ------------------------------------------------------------- intents

    private fun collect(intent: Intent?) {
        val uris = extract(intent) ?: return
        if (uris.isEmpty()) return
        synchronized(pending) { pending.addAll(uris) }
        // With nobody listening yet, they stay pending for takeInitial.
        if (sink != null) flushTo(null)
    }

    /** The files an intent carries, or null when it carries any file at all. */
    private fun extract(intent: Intent?): List<Uri>? {
        if (intent == null) return null
        return when (intent.action) {
            Intent.ACTION_SEND -> {
                val stream = streamOf(intent)
                if (stream != null) listOf(stream) else clipItems(intent)
            }

            Intent.ACTION_SEND_MULTIPLE -> {
                val streams = streamsOf(intent)
                if (streams.isNotEmpty()) streams else clipItems(intent)
            }

            Intent.ACTION_VIEW -> listOfNotNull(intent.data)

            else -> null
        }
    }

    @Suppress("DEPRECATION")
    private fun streamOf(intent: Intent): Uri? =
        intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri

    @Suppress("DEPRECATION")
    private fun streamsOf(intent: Intent): List<Uri> {
        val extra = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
        if (extra != null) return extra.filterNotNull()
        return emptyList()
    }

    /**
     * Some apps send the file as clip data instead of an extra, so it is worth
     * looking there rather than telling the user nothing arrived.
     */
    private fun clipItems(intent: Intent): List<Uri> {
        val clip = intent.clipData ?: return emptyList()
        return (0 until clip.itemCount).mapNotNull { clip.getItemAt(it).uri }
    }

    // -------------------------------------------------- handing over to Dart

    /**
     * Copies everything waiting into the inbox and passes the paths to Dart:
     * to [reply] when a method call is waiting for them, otherwise to the event
     * sink. Copying is the slow part, so it happens on its own thread.
     */
    private fun flushTo(reply: ((List<Map<String, String>>) -> Unit)?) {
        val uris: List<Uri> = synchronized(pending) {
            val take = ArrayList(pending)
            pending.clear()
            take
        }
        // A method call always has to be answered, even with nothing in it, or
        // the Dart future waiting on it would never complete.
        if (uris.isEmpty()) {
            reply?.invoke(emptyList())
            return
        }

        Thread {
            val files = ArrayList<Map<String, String>>(uris.size)
            uris.forEachIndexed { index, uri ->
                copyIn(uri, index)?.let { files.add(it) }
            }
            main.post {
                if (reply != null) reply.invoke(files) else sink?.success(files)
            }
        }.start()
    }

    /** Copies one shared URI into the inbox, or returns null if it cannot be read. */
    private fun copyIn(uri: Uri, index: Int): Map<String, String>? {
        // A file:// URI already is a path, so there is nothing to copy.
        if (uri.scheme == "file") {
            val path = uri.path ?: return null
            val file = File(path)
            if (!file.exists()) return null
            return mapOf("path" to path, "name" to file.name)
        }

        val name = displayName(uri) ?: "shared_${index + 1}"
        val dir = File(cacheDir, INBOX)
        if (!dir.exists() && !dir.mkdirs()) return null
        val target = uniqueIn(dir, safeName(name))

        return try {
            val input = contentResolver.openInputStream(uri) ?: return null
            input.use { source ->
                target.outputStream().use { output -> source.copyTo(output) }
            }
            mapOf("path" to target.absolutePath, "name" to name)
        } catch (e: Exception) {
            // A share that cannot be read should not leave a half-copied file
            // behind for the next run to trip over.
            target.delete()
            null
        }
    }

    /** The name the sending app shows for the file, which is what the UI wants. */
    private fun displayName(uri: Uri): String? {
        return try {
            contentResolver
                .query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor ->
                    if (cursor.moveToFirst() && !cursor.isNull(0)) cursor.getString(0) else null
                }
        } catch (e: Exception) {
            null
        }
    }

    /** Keeps the extension, drops anything that cannot live in a file name. */
    private fun safeName(name: String): String {
        val cleaned = name.replace(Regex("[\\\\/:*?\"<>|\\u0000-\\u001F]"), "_").trim()
        return if (cleaned.isEmpty()) "shared" else cleaned
    }

    /** Two shares of the same name must not overwrite each other. */
    private fun uniqueIn(dir: File, name: String): File {
        var candidate = File(dir, name)
        var n = 1
        while (candidate.exists()) {
            candidate = File(dir, "${n}_$name")
            n++
        }
        return candidate
    }
}
