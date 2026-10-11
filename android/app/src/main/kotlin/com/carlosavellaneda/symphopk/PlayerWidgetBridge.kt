package com.carlosavellaneda.symphopk

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Enlace entre los widgets de la pantalla de inicio y el reproductor (Dart).
 *
 * Dart envía `update` cada vez que cambia la canción o el estado, y los
 * botones de los widgets envían `toggle` / `next` / `previous` a Dart.
 *
 * Vive mientras exista el motor de Flutter, no la actividad: con música en
 * segundo plano el motor sigue activo y los widgets deben seguir funcionando.
 */
object PlayerWidgetBridge {
    private const val CHANNEL = "com.carlosavellaneda.symphopk/player_widget"

    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null

    /** `true` si hay un reproductor al que enviar órdenes. */
    val isConnected: Boolean
        get() = channel != null

    fun attach(context: Context, flutterEngine: FlutterEngine) {
        if (engine === flutterEngine) return
        detach()
        val appContext = context.applicationContext
        engine = flutterEngine
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "update") {
                    PlayerWidgetState(
                        songId = call.argument<Number>("songId")?.toLong() ?: PlayerWidgetState.NO_SONG,
                        title = call.argument<String>("title").orEmpty(),
                        artist = call.argument<String>("artist").orEmpty(),
                        playing = call.argument<Boolean>("playing") ?: false,
                    ).save(appContext)
                    PlayerWidgetProvider.updateAll(appContext)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
            // Dart puede haber arrancado antes de registrar este canal.
            channel.invokeMethod("requestState", null)
        }
        flutterEngine.addEngineLifecycleListener(object : FlutterEngine.EngineLifecycleListener {
            override fun onPreEngineRestart() {}

            override fun onEngineWillDestroy() {
                if (engine !== flutterEngine) return
                detach()
                // Sin motor nada suena: los widgets pasan a «abrir la app».
                PlayerWidgetState.load(appContext).copy(playing = false).save(appContext)
                PlayerWidgetProvider.updateAll(appContext)
            }
        })
    }

    private fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
        engine = null
    }

    /** Envía una orden al reproductor. Devuelve `false` si no hay a quién. */
    fun send(action: String): Boolean {
        val channel = channel ?: return false
        channel.invokeMethod(action, null)
        return true
    }
}
