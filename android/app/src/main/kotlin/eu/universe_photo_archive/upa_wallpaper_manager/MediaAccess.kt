package eu.universe_photo_archive.upa_wallpaper_manager

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.provider.DocumentsContract
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest

/**
 * Reads the user's own photos without any storage permission.
 *
 * The user grants lasting access to a folder through the system document
 * picker; that single grant covers every file inside it, survives reboots and
 * app updates, and needs no Play Store declaration. Images are therefore never
 * copied — they are read in place, both by the app and by the background
 * slideshow — and only small thumbnails are cached so Flutter has something to
 * display (it cannot render a `content://` URI directly).
 */
object MediaAccess {

    private val imageExtensions = setOf(
        "jpg", "jpeg", "png", "webp", "bmp", "gif", "heic", "heif"
    )

    /** Intent that asks the user to grant lasting access to a folder. */
    fun openFolderIntent(): Intent =
        Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
            )
        }

    /** Keeps the grant across restarts. Returns false when refused. */
    fun persistFolderAccess(context: Context, treeUri: Uri): Boolean {
        return try {
            context.contentResolver.takePersistableUriPermission(
                treeUri, Intent.FLAG_GRANT_READ_URI_PERMISSION
            )
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    fun releaseFolderAccess(context: Context, treeUri: Uri) {
        runCatching {
            context.contentResolver.releasePersistableUriPermission(
                treeUri, Intent.FLAG_GRANT_READ_URI_PERMISSION
            )
        }
    }

    fun hasAccess(context: Context, uri: String): Boolean =
        context.contentResolver.persistedUriPermissions.any {
            it.isReadPermission && uri.startsWith(it.uri.toString())
        }

    /**
     * Every image inside [treeUri], sub-folders included.
     *
     * [limit] guards against someone pointing the app at a folder holding tens
     * of thousands of files.
     */
    fun listImages(
        context: Context,
        treeUri: Uri,
        limit: Int = 5000
    ): List<Map<String, Any>> {
        val results = mutableListOf<Map<String, Any>>()
        val rootId = try {
            DocumentsContract.getTreeDocumentId(treeUri)
        } catch (e: Exception) {
            return results
        }
        collect(context, treeUri, rootId, results, limit)
        results.sortBy { (it["name"] as String).lowercase() }
        return results
    }

    private fun collect(
        context: Context,
        treeUri: Uri,
        documentId: String,
        into: MutableList<Map<String, Any>>,
        limit: Int
    ) {
        if (into.size >= limit) return

        val childrenUri =
            DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, documentId)
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED
        )

        val cursor = try {
            context.contentResolver.query(childrenUri, projection, null, null, null)
        } catch (e: Exception) {
            null
        } ?: return

        val subFolders = mutableListOf<String>()
        cursor.use {
            while (it.moveToNext() && into.size < limit) {
                val id = it.getString(0) ?: continue
                val name = it.getString(1) ?: continue
                val mime = it.getString(2) ?: ""

                if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                    subFolders.add(id)
                    continue
                }
                if (!isImage(mime, name)) continue

                into.add(
                    mapOf(
                        "uri" to DocumentsContract
                            .buildDocumentUriUsingTree(treeUri, id).toString(),
                        "name" to name,
                        "size" to it.getLong(3),
                        "lastModified" to it.getLong(4)
                    )
                )
            }
        }

        for (child in subFolders) {
            collect(context, treeUri, child, into, limit)
        }
    }

    private fun isImage(mime: String, name: String): Boolean {
        if (mime.startsWith("image/")) return true
        // Some providers report a generic mime type; fall back on the name.
        return imageExtensions.contains(name.substringAfterLast('.', "").lowercase())
    }

    /**
     * Path of a cached thumbnail for [uri], generating it on first use.
     *
     * Flutter cannot display a `content://` URI, so the UI is fed these small
     * JPEGs instead — tens of kilobytes each, against several megabytes for
     * the originals we deliberately do not copy.
     */
    fun thumbnail(context: Context, uri: Uri, maxSize: Int): String? {
        return try {
            val dir = File(context.cacheDir, "saf_thumbs").apply { mkdirs() }
            val target = File(dir, "${hash(uri.toString())}_$maxSize.jpg")
            if (target.exists() && target.length() > 0) return target.absolutePath

            // Measure first so a full-resolution photo is never fully decoded.
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            context.contentResolver.openInputStream(uri)?.use {
                BitmapFactory.decodeStream(it, null, bounds)
            } ?: return null
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

            var sample = 1
            while (bounds.outWidth / (sample * 2) >= maxSize ||
                bounds.outHeight / (sample * 2) >= maxSize
            ) {
                sample *= 2
            }

            val options = BitmapFactory.Options().apply { inSampleSize = sample }
            val bitmap = context.contentResolver.openInputStream(uri)?.use {
                BitmapFactory.decodeStream(it, null, options)
            } ?: return null

            FileOutputStream(target).use { out ->
                bitmap.compress(Bitmap.CompressFormat.JPEG, 85, out)
            }
            bitmap.recycle()
            target.absolutePath
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    private fun hash(value: String): String {
        val digest = MessageDigest.getInstance("SHA-1").digest(value.toByteArray())
        return digest.joinToString("") { "%02x".format(it) }.take(24)
    }
}
