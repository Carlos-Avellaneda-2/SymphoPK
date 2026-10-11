package com.carlosavellaneda.symphopk

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// AudioServiceActivity reutiliza el FlutterEngine del servicio de audio, de
// modo que la UI se reconecta a la reproducción en curso al reabrir la app.
class MainActivity : AudioServiceActivity() {
    private var mediaLibraryChannel: MediaLibraryChannel? = null

    // Respuesta pendiente mientras el selector de carpetas está abierto.
    private var pendingFolderResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        mediaLibraryChannel = MediaLibraryChannel(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
            onPickFolder = ::pickLyricsFolder,
        )
        // Sobrevive a la actividad: se libera cuando se destruye el motor.
        PlayerWidgetBridge.attach(applicationContext, flutterEngine)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        mediaLibraryChannel?.dispose()
        mediaLibraryChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    /** Abre el selector del sistema para conceder una carpeta con letras. */
    private fun pickLyricsFolder(result: MethodChannel.Result) {
        if (pendingFolderResult != null) {
            result.success(false)
            return
        }
        pendingFolderResult = result
        try {
            startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE), REQUEST_LYRICS_FOLDER)
        } catch (e: ActivityNotFoundException) {
            pendingFolderResult = null
            result.success(false)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_LYRICS_FOLDER) return
        val result = pendingFolderResult ?: return
        pendingFolderResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(false)
            return
        }
        try {
            SiblingFileReader.persist(applicationContext, uri)
            result.success(true)
        } catch (e: SecurityException) {
            result.success(false)
        }
    }

    private companion object {
        const val REQUEST_LYRICS_FOLDER = 4107
    }
}
