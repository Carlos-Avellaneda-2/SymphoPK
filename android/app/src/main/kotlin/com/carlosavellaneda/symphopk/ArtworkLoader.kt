package com.carlosavellaneda.symphopk

import android.content.ContentUris
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.util.Size
import java.io.IOException

/** Carga la carátula de una canción de MediaStore. Debe llamarse fuera del hilo principal. */
object ArtworkLoader {

    private val collection: Uri
        get() = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        } else {
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        }

    /** Devuelve la carátula con lado aproximado [size], o `null` si no tiene o no se puede leer. */
    fun load(context: Context, songId: Long, size: Int): Bitmap? {
        val uri = ContentUris.withAppendedId(collection, songId)
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                context.contentResolver.loadThumbnail(uri, Size(size, size), null)
            } else {
                embeddedPicture(context, uri, size)
            }
        } catch (e: IOException) {
            null // el archivo no tiene carátula
        } catch (e: SecurityException) {
            null // sin permiso de lectura de audio
        } catch (e: RuntimeException) {
            null // archivo dañado o formato no soportado
        }
    }

    /** Antes de Android 10 no existe `loadThumbnail`: se lee la imagen embebida. */
    private fun embeddedPicture(context: Context, uri: Uri, size: Int): Bitmap? {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(context, uri)
            val bytes = retriever.embeddedPicture ?: return null
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
            var sample = 1
            while (bounds.outWidth / (sample * 2) >= size && bounds.outHeight / (sample * 2) >= size) {
                sample *= 2
            }
            val options = BitmapFactory.Options().apply { inSampleSize = sample }
            return BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
        } finally {
            retriever.release()
        }
    }
}
