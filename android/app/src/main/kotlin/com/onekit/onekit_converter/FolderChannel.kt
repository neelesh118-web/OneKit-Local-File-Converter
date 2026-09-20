package com.onekit.onekit_converter

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Converting a whole folder, without asking for storage access.
 *
 * The point of this channel is what it does *not* need. Android lets a user
 * hand an app one folder through its own picker, and what comes back is a tree
 * of `content://` URIs with a read grant for this app alone — the same kind of
 * grant a shared file arrives with. No storage permission is involved, and
 * adding one is exactly what this app has promised not to do.
 *
 * The engines, though, work on paths. And it is not enough to turn the tree
 * into a path: under scoped storage an app cannot read other apps' files by
 * path at all, grant or no grant, which is why the file picker's own directory
 * path is not something to build on here. So each file is copied into the app's
 * own working directory as it is found, the way a shared file is copied before
 * Dart is told about it, and Dart is handed ordinary paths.
 *
 * Only the extensions Dart sends are copied. A folder is picked for what is in
 * it that this app can convert — a phone's camera folder holds thumbnails,
 * `.nomedia` markers and databases too, and copying a few thousand files to
 * queue forty of them would be dishonest about what the wait was for.
 *
 * Everything runs off the main thread: a folder of videos is minutes of I/O.
 */
object FolderChannel {

    private const val CHANNEL = "onekit/folder"

    /** Any small number: this app has one activity result to route. The
     *  embedding's own activity results use codes of their own. */
    private const val REQUEST = 7421

    /**
     * Where the copies go. Under `lfc_work` on purpose: that is what Settings'
     * "Clear working files" sweeps, so nothing here outlives the user's ability
     * to clear it.
     */
    private const val INBOX = "lfc_work/folder"

    private const val DIRECTORY = DocumentsContract.Document.MIME_TYPE_DIR

    private val main = Handler(Looper.getMainLooper())

    /** The pick in flight, or null. One at a time: a second pick has nowhere to
     *  put its answer, and the picker is a modal screen anyway. */
    private var pending: MethodChannel.Result? = null

    /** The extensions Dart asked for, held across the gap while the picker is
     *  on screen. */
    private var wanted: Set<String> = emptySet()

    fun attach(activity: Activity, messenger: BinaryMessenger) {
        // A pick left over from an earlier engine can never be answered: the
        // Dart side that was waiting for it is gone. Dropping it here is what
        // keeps the picker usable afterwards, since a stale result would
        // otherwise be mistaken for one already on screen and every later pick
        // answered as cancelled — a button that looks broken until the app is
        // restarted.
        pending = null

        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "pick" -> pick(activity, call, result)
                else -> result.notImplemented()
            }
        }
    }

    // startActivityForResult is deprecated in favour of an activity result
    // registry, which needs a ComponentActivity — and the FlutterActivity this
    // app is built on is a plain one. The picker still works exactly as it
    // always has.
    @Suppress("DEPRECATION")
    private fun pick(activity: Activity, call: MethodCall, result: MethodChannel.Result) {
        if (pending != null) {
            result.success(cancelled())
            return
        }
        pending = result
        wanted = (call.argument<List<*>>("extensions") ?: emptyList<Any>())
            .filterIsInstance<String>()
            .map { it.lowercase().trimStart('.') }
            .toSet()

        // Android's own folder picker. It hands back a tree the app is lent for
        // as long as this activity lives, which is why the copy happens now
        // rather than a path being remembered for later.
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
        }
        try {
            activity.startActivityForResult(intent, REQUEST)
        } catch (e: ActivityNotFoundException) {
            // A device with no documents picker at all. Nothing to pick with.
            pending = null
            result.success(mapOf<String, Any?>("problem" to "no folder picker on this device"))
        }
    }

    /**
     * Called by the activity when the picker comes back. Returns whether this
     * channel was the one that asked for it, so a second request code could be
     * routed the same way later.
     */
    fun onActivityResult(
        context: Context,
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ): Boolean {
        if (requestCode != REQUEST) return false
        val result = pending ?: return true
        pending = null

        val tree = if (resultCode == Activity.RESULT_OK) data?.data else null
        if (tree == null) {
            // Backing out of the picker is an answer, not a failure.
            result.success(cancelled())
            return true
        }

        val extensions = wanted
        Thread {
            val answer = try {
                read(context, tree, extensions)
            } catch (e: Exception) {
                // The tree could not be walked after all — a revoked grant, a
                // provider that stopped answering. Reported as a short fact
                // rather than as an empty folder, which would look like the user
                // picked the wrong thing; the wording belongs to Dart.
                mapOf<String, Any?>("problem" to "unreadable")
            }
            main.post { result.success(answer) }
        }.start()
        return true
    }

    private fun cancelled(): Map<String, Any?> =
        mapOf("files" to emptyList<Any>(), "skipped" to 0, "cancelled" to true)

    private fun read(context: Context, tree: Uri, extensions: Set<String>): Map<String, Any?> {
        val into = File(context.cacheDir, "$INBOX/${System.currentTimeMillis()}")
        if (!into.exists() && !into.mkdirs()) {
            return mapOf<String, Any?>("problem" to "no space")
        }

        val files = mutableListOf<Map<String, Any?>>()
        val tally = Tally()
        walk(
            context,
            tree,
            DocumentsContract.getTreeDocumentId(tree),
            into,
            "",
            extensions,
            files,
            tally,
        )

        return mapOf(
            "folder" to (nameOf(context, tree) ?: "folder"),
            "root" to into.absolutePath,
            "files" to files,
            "skipped" to tally.skipped,
        )
    }

    /** Walks one directory, recursing into the ones that are not hidden. */
    private fun walk(
        context: Context,
        tree: Uri,
        parentId: String,
        into: File,
        relative: String,
        extensions: Set<String>,
        out: MutableList<Map<String, Any?>>,
        tally: Tally,
    ) {
        for (child in children(context, tree, parentId)) {
            if (child.mime == DIRECTORY) {
                // Hidden directories are not what anyone picks a folder for, and
                // on a photo library they are the app's own scratch space.
                if (child.name.startsWith(".")) continue
                walk(
                    context,
                    tree,
                    child.id,
                    into,
                    if (relative.isEmpty()) child.name else "$relative/${child.name}",
                    extensions,
                    out,
                    tally,
                )
                continue
            }

            if (extensionOf(child.name) !in extensions) {
                tally.skipped++
                continue
            }

            val copied = copy(
                context,
                tree,
                child.id,
                child.name,
                if (relative.isEmpty()) into else File(into, relative),
            )
            if (copied != null) out.add(copied) else tally.skipped++
        }
    }

    private class Child(val id: String, val name: String, val mime: String)

    private fun children(context: Context, tree: Uri, parentId: String): List<Child> {
        val uri = DocumentsContract.buildChildDocumentsUriUsingTree(tree, parentId)
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
        )
        val out = mutableListOf<Child>()
        context.contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
            val idAt = cursor.getColumnIndex(projection[0])
            val nameAt = cursor.getColumnIndex(projection[1])
            val mimeAt = cursor.getColumnIndex(projection[2])
            while (cursor.moveToNext()) {
                val id = if (idAt >= 0) cursor.getString(idAt) else null
                val name = if (nameAt >= 0) cursor.getString(nameAt) else null
                if (id == null || name.isNullOrEmpty()) continue
                out.add(Child(id, name, if (mimeAt >= 0) cursor.getString(mimeAt).orEmpty() else ""))
            }
        }
        return out
    }

    /** Copies one document in, keeping its folder so names cannot collide. */
    private fun copy(
        context: Context,
        tree: Uri,
        id: String,
        name: String,
        into: File,
    ): Map<String, Any?>? {
        if (!into.exists() && !into.mkdirs()) return null
        val file = uniqueTo(into, safeName(name))

        return try {
            val input = context.contentResolver.openInputStream(
                DocumentsContract.buildDocumentUriUsingTree(tree, id),
            ) ?: return null
            input.use { source -> file.outputStream().use { target -> source.copyTo(target) } }
            mapOf("path" to file.absolutePath, "name" to name)
        } catch (e: Exception) {
            // A half-written copy would be converted from its stub, so it goes.
            file.delete()
            null
        }
    }

    private class Tally {
        var skipped = 0
    }

    /** Keeps the extension: the format is decided from it. */
    private fun safeName(name: String): String {
        val cleaned = name.replace(Regex("[\\\\/:*?\"<>|\\u0000-\\u001F]"), "_").trim()
        return if (cleaned.isEmpty()) "file" else cleaned
    }

    /** Two files of the same name in one folder must not become one file. */
    private fun uniqueTo(dir: File, name: String): File {
        var candidate = File(dir, name)
        var n = 1
        val dot = name.lastIndexOf('.')
        while (candidate.exists()) {
            candidate = if (dot > 0) {
                File(dir, "${name.take(dot)} ($n)${name.substring(dot)}")
            } else {
                File(dir, "$name ($n)")
            }
            n++
        }
        return candidate
    }

    /** Lowercase, no dot, empty when there is none. `tar.gz` matches on `gz`,
     *  which is enough to decide whether to copy it: Dart resolves the real
     *  compound format from the name it gets back. */
    private fun extensionOf(name: String): String {
        val dot = name.lastIndexOf('.')
        return if (dot <= 0 || dot == name.length - 1) "" else name.substring(dot + 1).lowercase()
    }

    /** The picked folder's own name, for the queue rows and the message. */
    private fun nameOf(context: Context, tree: Uri): String? {
        val uri = DocumentsContract.buildDocumentUriUsingTree(
            tree,
            DocumentsContract.getTreeDocumentId(tree),
        )
        return try {
            context.contentResolver.query(
                uri,
                arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }
        } catch (e: Exception) {
            null
        }
    }
}
