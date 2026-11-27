package com.snowdrop.app.data

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Log
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import androidx.documentfile.provider.DocumentFile
import java.io.File

class ReceivedFileStorage(context: Context) {
    private val appContext = context.applicationContext
    private val prefs = appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun downloadLocationName(): String =
        prefs.getString(KEY_CUSTOM_DOWNLOAD_NAME, null)?.takeIf { it.isNotBlank() } ?: DEFAULT_LOCATION_NAME

    fun getDownloadTreeUri(): Uri? {
        val raw = prefs.getString(KEY_CUSTOM_DOWNLOAD_URI, null) ?: return null
        return runCatching { Uri.parse(raw) }.getOrNull()
    }

    fun setCustomDownloadTreeUri(treeUri: Uri?): String {
        if (treeUri == null) {
            prefs.edit()
                .remove(KEY_CUSTOM_DOWNLOAD_URI)
                .remove(KEY_CUSTOM_DOWNLOAD_NAME)
                .apply()
            return DEFAULT_LOCATION_NAME
        }

        val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        runCatching {
            appContext.contentResolver.takePersistableUriPermission(treeUri, flags)
        }.onFailure { err ->
            Log.w(TAG, "Unable to persist SAF URI permission", err)
        }

        val name = DocumentFile.fromTreeUri(appContext, treeUri)?.name
            ?.takeIf { it.isNotBlank() }
            ?: "Custom Folder"

        prefs.edit()
            .putString(KEY_CUSTOM_DOWNLOAD_URI, treeUri.toString())
            .putString(KEY_CUSTOM_DOWNLOAD_NAME, name)
            .apply()
        return name
    }

    fun saveReceivedFile(filePath: String): String? {
        val sourceFile = File(filePath)
        if (!sourceFile.exists() || !sourceFile.isFile) return null

        val fileName = sourceFile.name
        val mimeType = resolveMimeType(fileName)

        getDownloadTreeUri()?.let { treeUri ->
            saveToCustomSafTree(treeUri, sourceFile, fileName, mimeType)?.let { return it }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveToMediaStorePending(sourceFile, fileName, mimeType)?.let { return it }
        } else {
            saveToLegacyDownloads(sourceFile, fileName)?.let { return it }
        }

        return runCatching {
            FileProvider.getUriForFile(
                appContext,
                "${appContext.packageName}.fileprovider",
                sourceFile
            ).toString()
        }.getOrNull()
    }

    fun migrateLegacyDownloads() {
        runCatching {
            val legacyBase = appContext.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS) ?: return
            val legacyDir = File(legacyBase, "Snowdrop")
            if (!legacyDir.exists() || !legacyDir.isDirectory) return
            legacyDir.listFiles()?.forEach { file ->
                if (file.isFile) {
                    saveReceivedFile(file.absolutePath)
                }
            }
        }.onFailure { err ->
            Log.w(TAG, "Failed migrating legacy downloads", err)
        }
    }

    private fun saveToCustomSafTree(
        treeUri: Uri,
        sourceFile: File,
        fileName: String,
        mimeType: String
    ): String? = runCatching {
        val dir = DocumentFile.fromTreeUri(appContext, treeUri) ?: return null
        val targetDoc = dir.createFile(mimeType, fileName) ?: return null
        appContext.contentResolver.openOutputStream(targetDoc.uri)?.use { out ->
            sourceFile.inputStream().use { input -> input.copyTo(out) }
        } ?: return null
        sourceFile.delete()
        targetDoc.uri.toString()
    }.onFailure { err ->
        Log.e(TAG, "Failed saving to custom SAF folder, falling back", err)
    }.getOrNull()

    private fun saveToMediaStorePending(
        sourceFile: File,
        fileName: String,
        mimeType: String
    ): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        val resolver = appContext.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            put(MediaStore.MediaColumns.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/Snowdrop")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: return null
        return try {
            resolver.openOutputStream(uri)?.use { out ->
                sourceFile.inputStream().use { input -> input.copyTo(out) }
            } ?: throw IllegalStateException("Null MediaStore output stream")

            val publishValues = ContentValues().apply {
                put(MediaStore.MediaColumns.IS_PENDING, 0)
            }
            resolver.update(uri, publishValues, null, null)
            sourceFile.delete()
            uri.toString()
        } catch (t: Throwable) {
            runCatching { resolver.delete(uri, null, null) }
            Log.e(TAG, "Failed saving to MediaStore.Downloads", t)
            null
        }
    }

    @Suppress("DEPRECATION")
    private fun saveToLegacyDownloads(sourceFile: File, fileName: String): String? = runCatching {
        val pubDir = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
            "Snowdrop"
        ).apply { mkdirs() }
        val destFile = resolveUniqueDestination(pubDir, fileName)
        sourceFile.copyTo(destFile, overwrite = false)
        sourceFile.delete()
        MediaScannerConnection.scanFile(appContext, arrayOf(destFile.absolutePath), null, null)
        FileProvider.getUriForFile(
            appContext,
            "${appContext.packageName}.fileprovider",
            destFile
        ).toString()
    }.onFailure { err ->
        Log.e(TAG, "Failed saving to public Downloads directory", err)
    }.getOrNull()

    private fun resolveUniqueDestination(dir: File, fileName: String): File {
        val first = File(dir, fileName)
        if (!first.exists()) return first
        val dot = fileName.lastIndexOf('.')
        val stem = if (dot > 0) fileName.substring(0, dot) else fileName
        val ext = if (dot > 0) fileName.substring(dot) else ""
        for (i in 1..10_000) {
            val candidate = File(dir, "$stem ($i)$ext")
            if (!candidate.exists()) return candidate
        }
        return File(dir, "$stem-${System.currentTimeMillis()}$ext")
    }

    private fun resolveMimeType(fileName: String): String {
        val ext = fileName.substringAfterLast('.', "").lowercase()
        if (ext.isEmpty()) return "application/octet-stream"
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "application/octet-stream"
    }

    companion object {
        private const val TAG = "ReceivedFileStorage"
        private const val PREFS_NAME = "snowdrop_prefs"
        private const val KEY_CUSTOM_DOWNLOAD_URI = "custom_download_uri"
        private const val KEY_CUSTOM_DOWNLOAD_NAME = "custom_download_name"
        const val DEFAULT_LOCATION_NAME = "Downloads/Snowdrop"
    }
}
