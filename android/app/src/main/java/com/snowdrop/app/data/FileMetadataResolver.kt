package com.snowdrop.app.data

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import com.snowdrop.app.domain.StagedFile

object FileMetadataResolver {
    fun resolve(context: Context, uri: Uri): StagedFile {
        var name: String? = null
        var size = -1L

        runCatching {
            context.contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
                null,
                null,
                null
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val nameIdx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    val sizeIdx = cursor.getColumnIndex(OpenableColumns.SIZE)
                    if (nameIdx >= 0) {
                        name = cursor.getString(nameIdx)
                    }
                    if (sizeIdx >= 0 && !cursor.isNull(sizeIdx)) {
                        size = cursor.getLong(sizeIdx)
                    }
                }
            }
        }

        if (size <= 0L) {
            size = runCatching {
                context.contentResolver.openAssetFileDescriptor(uri, "r")?.use { it.length } ?: -1L
            }.getOrDefault(-1L)
        }
        if (size <= 0L) {
            size = runCatching {
                context.contentResolver.openFileDescriptor(uri, "r")?.use { it.statSize } ?: 0L
            }.getOrDefault(0L)
        }

        val resolvedName = name?.takeIf { it.isNotBlank() }
            ?: uri.lastPathSegment?.substringAfterLast('/')?.takeIf { it.isNotBlank() }
            ?: "file"

        return StagedFile(
            uriString = uri.toString(),
            name = resolvedName,
            byteSize = size.coerceAtLeast(0L)
        )
    }

    fun resolveAll(context: Context, uris: List<Uri>): List<StagedFile> =
        uris.distinct().map { resolve(context, it) }
}
