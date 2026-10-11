package com.carlosavellaneda.symphopk

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

// AudioServiceActivity reutiliza el FlutterEngine del servicio de audio, de
// modo que la UI se reconecta a la reproducción en curso al reabrir la app.
class MainActivity : AudioServiceActivity() {
    private var mediaLibraryChannel: MediaLibraryChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        mediaLibraryChannel = MediaLibraryChannel(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
        )
        // Sobrevive a la actividad: se libera cuando se destruye el motor.
        PlayerWidgetBridge.attach(applicationContext, flutterEngine)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        mediaLibraryChannel?.dispose()
        mediaLibraryChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
