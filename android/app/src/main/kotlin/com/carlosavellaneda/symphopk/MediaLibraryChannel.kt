package com.carlosavellaneda.symphopk

import android.content.ContentUris
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Size
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.util.concurrent.Executors

/**
 * Canal con Dart para leer la biblioteca de audio desde MediaStore.
 *
 * Solo necesita el permiso de lectura de audio (READ_MEDIA_AUDIO o
 * READ_EXTERNAL_STORAGE según la versión); pedirlo es responsabilidad del
 * lado Dart. Las consultas corren fuera del hilo principal.
 */
class MediaLibraryChannel(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL)
    private val executor = Executors.newFixedThreadPool(4)
    private val mainHandler = Handler(Looper.getMainLooper())

    private val collection: Uri =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        } else {
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        }

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        executor.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "querySongs" -> runInBackground(result) { querySongs() }
            "artwork" -> {
                val id = call.argument<Number>("id")?.toLong()
                val size = call.argument<Int>("size") ?: 400
                if (id == null) {
                    result.error("bad_args", "Falta el id de la canción", null)
                } else {
                    runInBackground(result) { artwork(id, size) }
                }
            }
            else -> result.notImplemented()
        }
    }

    /** Ejecuta [block] en segundo plano y responde una sola vez en el hilo principal. */
    private fun runInBackground(result: MethodChannel.Result, block: () -> Any?) {
        executor.execute {
            try {
                val value = block()
                mainHandler.post { result.success(value) }
            } catch (e: SecurityException) {
                mainHandler.post { result.error("permission_denied", e.message, null) }
            } catch (e: Exception) {
                mainHandler.post { result.error("query_failed", e.message, null) }
            }
        }
    }

    private fun querySongs(): List<Map<String, Any?>> {
        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.DISPLAY_NAME,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ARTIST_ID,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.ALBUM_ID,
            MediaStore.Audio.Media.TRACK,
            MediaStore.Audio.Media.DATE_ADDED,
            COLUMN_DURATION,
            // Ruta del archivo: solo se usa para agrupar por carpetas, nunca
            // para abrirlo (la reproducción va por el URI de contenido).
            MediaStore.Audio.Media.DATA,
        )
        val songs = ArrayList<Map<String, Any?>>()
        context.contentResolver.query(
            collection,
            projection,
            // Deja fuera tonos, alarmas y notificaciones.
            "${MediaStore.Audio.Media.IS_MUSIC} != 0",
            null,
            "${MediaStore.Audio.Media.TITLE} COLLATE NOCASE ASC",
        )?.use { cursor ->
            val id = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val title = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val displayName = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DISPLAY_NAME)
            val artist = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val artistId = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST_ID)
            val album = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
            val albumId = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM_ID)
            val track = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TRACK)
            val dateAdded = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_ADDED)
            val duration = cursor.getColumnIndexOrThrow(COLUMN_DURATION)
            val path = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)

            while (cursor.moveToNext()) {
                val songId = cursor.getLong(id)
                songs.add(
                    mapOf(
                        "id" to songId,
                        "uri" to ContentUris.withAppendedId(collection, songId).toString(),
                        "title" to cursor.getString(title),
                        "displayName" to cursor.getString(displayName),
                        "artist" to cursor.getString(artist),
                        "artistId" to cursor.longOrNull(artistId),
                        "album" to cursor.getString(album),
                        "albumId" to cursor.longOrNull(albumId),
                        "track" to cursor.longOrNull(track),
                        "dateAdded" to cursor.longOrNull(dateAdded),
                        "durationMs" to (cursor.longOrNull(duration) ?: 0L),
                        "path" to cursor.getString(path),
                    ),
                )
            }
        }
        return songs
    }

    /** Carátula de la canción como JPEG, o `null` si no tiene. */
    private fun artwork(songId: Long, size: Int): ByteArray? {
        val uri = ContentUris.withAppendedId(collection, songId)
        val bitmap = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                context.contentResolver.loadThumbnail(uri, Size(size, size), null)
            } catch (e: IOException) {
                null // el archivo no tiene carátula
            }
        } else {
            embeddedPicture(uri, size)
        } ?: return null

        return ByteArrayOutputStream().use { stream ->
            bitmap.compress(Bitmap.CompressFormat.JPEG, 90, stream)
            bitmap.recycle()
            stream.toByteArray()
        }
    }

    /** Antes de Android 10 no existe `loadThumbnail`: se lee la imagen embebida. */
    private fun embeddedPicture(uri: Uri, size: Int): Bitmap? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(context, uri)
            val bytes = retriever.embeddedPicture ?: return null
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
            var sample = 1
            while (bounds.outWidth / (sample * 2) >= size && bounds.outHeight / (sample * 2) >= size) {
                sample *= 2
            }
            val options = BitmapFactory.Options().apply { inSampleSize = sample }
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
        } catch (e: RuntimeException) {
            null
        } finally {
            retriever.release()
        }
    }

    private fun android.database.Cursor.longOrNull(index: Int): Long? =
        if (isNull(index)) null else getLong(index)

    private companion object {
        const val CHANNEL = "com.carlosavellaneda.symphopk/media_library"

        // `MediaStore.Audio.Media.DURATION` solo existe como constante desde
        // API 29, pero la columna está disponible en todas las versiones.
        const val COLUMN_DURATION = "duration"
    }
}
