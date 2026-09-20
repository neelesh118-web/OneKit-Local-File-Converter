package com.onekit.onekit_converter

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException

/**
 * Puts a finished conversion where the rest of the phone can find it.
 *
 * A conversion writes into the app's own storage, which is the only place this
 * app may write without asking for a permission — and it is also a place no
 * gallery, no Downloads app and no file manager shows. The result is findable
 * only from inside OneKit, which is not where anyone looks for a photo they
 * just converted. This channel hands a copy to MediaStore instead, in a folder
 * named after the app, so the system's own apps list it.
 *
 * No permission is involved. On Android 10 and up, an app may insert into the
 * shared media collections on its own behalf; the copy is owned by this app,
 * carries a pending flag until it is fully written so nothing else can see half
 * a file, and is deleted again if the copy fails. Below Android 10 the same
 * write would need WRITE_EXTERNAL_STORAGE, which this app does not request and
 * will not, so those devices are told the truth: not saved, no copy.
 *
 * Only facts cross the channel, never sentences. The wording lives in Dart,
 * beside the rest of the app's copy.
 */
object MediaStoreChannel {

    private const val CHANNEL = "onekit/media_store"

    fun attach(context: Context, messenger: BinaryMessenger) {
        val app = context.applicationContext
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "publish" -> publish(app, call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun publish(context: Context, call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        val name = call.argument<String>("name")
        if (path.isNullOrEmpty() || name.isNullOrEmpty()) {
            result.success(mapOf("saved" to false, "reason" to "missing"))
            return
        }
        val mime = call.argument<String>("mime") ?: "application/octet-stream"
        val collection = call.argument<String>("collection") ?: "downloads"

        // A converted video can be hundreds of megabytes, so the copy runs off
        // the main thread. The reply still has to come back on it.
        Thread {
            val answer = try {
                write(context, path, name, mime, collection)
            } catch (e: Exception) {
                mapOf<String, Any?>("saved" to false, "reason" to "failed", "detail" to e.message)
            }
            Handler(Looper.getMainLooper()).post { result.success(answer) }
        }.start()
    }

    /**
     * Copies [path] into the public collection [collection] under a OneKit
     * folder, and makes it visible. Returns what happened as facts, never
     * throws: a conversion that succeeded must not be reported as failed
     * because a second copy of its result could not be written.
     */
    private fun write(
        context: Context,
        path: String,
        name: String,
        mime: String,
        collection: String,
    ): Map<String, Any?> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            // See the class comment: the alternative here is a storage
            // permission, and this app does not ask for one.
            return mapOf("saved" to false, "reason" to "unsupported")
        }

        val source = File(path)
        if (!source.exists() || !source.canRead()) {
            return mapOf("saved" to false, "reason" to "unreadable")
        }

        val folder = folderFor(collection)
        // Chosen here rather than in a function of its own so that the version
        // check above is plainly what makes naming the Downloads collection
        // safe: it arrived in Android 10, like the relative path and the
        // pending flag beside it.
        val collectionUri = when (collection) {
            "images" -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            "video" -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            "audio" -> MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
            else -> MediaStore.Downloads.EXTERNAL_CONTENT_URI
        }
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, folder)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }

        val resolver = context.contentResolver
        val uri: Uri = resolver.insert(collectionUri, values)
            ?: return mapOf("saved" to false, "reason" to "refused")

        try {
            val output = resolver.openOutputStream(uri)
                ?: throw IOException("no output stream for $uri")
            output.use { out -> source.inputStream().use { input -> input.copyTo(out) } }
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        } catch (e: Exception) {
            // An entry that never finished would sit in the gallery as an
            // unreadable file the user cannot explain.
            resolver.delete(uri, null, null)
            throw e
        }

        return mapOf("saved" to true, "location" to folder.trimEnd('/'), "uri" to uri.toString())
    }

    /** Where the copy lands, as the gallery and Files apps show it. */
    private fun folderFor(collection: String): String = when (collection) {
        "images" -> "Pictures/OneKit/"
        "video" -> "Movies/OneKit/"
        "audio" -> "Music/OneKit/"
        else -> "Download/OneKit/"
    }
}
