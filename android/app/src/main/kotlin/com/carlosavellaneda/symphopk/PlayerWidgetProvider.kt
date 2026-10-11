package com.carlosavellaneda.symphopk

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.widget.RemoteViews
import java.util.concurrent.Executors

/** Widget de 4×1: carátula, título y controles en una fila. */
class PlayerWidgetSmall : PlayerWidgetProvider()

/** Widget de 3×2: carátula grande con título y controles al lado. */
class PlayerWidgetLarge : PlayerWidgetProvider()

/**
 * Base de los widgets del reproductor. Ambos muestran lo mismo con distinto
 * diseño, así que comparten el pintado.
 */
abstract class PlayerWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, appWidgetIds: IntArray) {
        // La carátula se lee en segundo plano; goAsync mantiene vivo el
        // proceso hasta terminar.
        val pending = goAsync()
        updateAll(context.applicationContext) { pending.finish() }
    }

    companion object {
        private const val ART_SIZE = 256
        private val executor = Executors.newSingleThreadExecutor()

        // Evita releer la carátula cuando solo cambia play/pausa.
        private var cachedArtSongId = PlayerWidgetState.NO_SONG
        private var cachedArt: Bitmap? = null

        /** Repinta todos los widgets colocados con el estado guardado. */
        fun updateAll(context: Context, onDone: () -> Unit = {}) {
            executor.execute {
                try {
                    val manager = AppWidgetManager.getInstance(context)
                    val state = PlayerWidgetState.load(context)
                    val art = if (state.hasSong) artFor(context, state.songId) else null
                    render(context, manager, PlayerWidgetSmall::class.java, R.layout.widget_player_small, state, art)
                    render(context, manager, PlayerWidgetLarge::class.java, R.layout.widget_player_large, state, art)
                } finally {
                    onDone()
                }
            }
        }

        private fun render(
            context: Context,
            manager: AppWidgetManager,
            provider: Class<out PlayerWidgetProvider>,
            layout: Int,
            state: PlayerWidgetState,
            art: Bitmap?,
        ) {
            val ids = manager.getAppWidgetIds(ComponentName(context, provider))
            if (ids.isEmpty()) return

            // Solo hay a quién mandar órdenes si el reproductor está en marcha
            // y tiene una canción; si no, cualquier toque abre la app.
            val controllable = PlayerWidgetBridge.isConnected && state.hasSong
            val playing = controllable && state.playing
            val openApp = openAppIntent(context)

            val views = RemoteViews(context.packageName, layout).apply {
                setTextViewText(
                    R.id.widget_title,
                    if (state.hasSong) state.title else context.getString(R.string.widget_empty_title),
                )
                setTextViewText(
                    R.id.widget_artist,
                    if (state.hasSong) state.artist else context.getString(R.string.widget_empty_subtitle),
                )
                if (art != null) {
                    setImageViewBitmap(R.id.widget_art, art)
                } else {
                    setImageViewResource(R.id.widget_art, R.drawable.widget_art_placeholder)
                }
                setImageViewResource(
                    R.id.widget_play,
                    if (playing) R.drawable.ic_widget_pause else R.drawable.ic_widget_play,
                )
                setContentDescription(
                    R.id.widget_play,
                    context.getString(if (playing) R.string.widget_pause else R.string.widget_play),
                )

                setOnClickPendingIntent(R.id.widget_root, openApp)
                setOnClickPendingIntent(
                    R.id.widget_play,
                    if (controllable) actionIntent(context, PlayerWidgetActionReceiver.ACTION_TOGGLE) else openApp,
                )
                setOnClickPendingIntent(
                    R.id.widget_next,
                    if (controllable) actionIntent(context, PlayerWidgetActionReceiver.ACTION_NEXT) else openApp,
                )
                setOnClickPendingIntent(
                    R.id.widget_prev,
                    if (controllable) actionIntent(context, PlayerWidgetActionReceiver.ACTION_PREVIOUS) else openApp,
                )
            }
            manager.updateAppWidget(ids, views)
        }

        private fun artFor(context: Context, songId: Long): Bitmap? {
            if (songId == cachedArtSongId) return cachedArt
            val art = ArtworkLoader.load(context, songId, ART_SIZE)?.let(::roundCorners)
            cachedArtSongId = songId
            cachedArt = art
            return art
        }

        /** RemoteViews no recorta esquinas: se redondean en el propio bitmap. */
        private fun roundCorners(source: Bitmap): Bitmap {
            val side = minOf(source.width, source.height)
            val square = Bitmap.createBitmap(
                source,
                (source.width - side) / 2,
                (source.height - side) / 2,
                side,
                side,
            )
            val output = Bitmap.createBitmap(side, side, Bitmap.Config.ARGB_8888)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                shader = BitmapShader(square, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
            }
            val radius = side * 0.18f
            Canvas(output).drawRoundRect(RectF(0f, 0f, side.toFloat(), side.toFloat()), radius, radius, paint)
            return output
        }

        fun openAppIntent(context: Context): PendingIntent {
            val intent = Intent(context, MainActivity::class.java)
                .setAction(Intent.ACTION_MAIN)
                .addCategory(Intent.CATEGORY_LAUNCHER)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
            return PendingIntent.getActivity(
                context,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private fun actionIntent(context: Context, action: String): PendingIntent {
            val intent = Intent(context, PlayerWidgetActionReceiver::class.java).setAction(action)
            return PendingIntent.getBroadcast(
                context,
                action.hashCode(),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }
}

/** Recibe los toques en los botones de los widgets. */
class PlayerWidgetActionReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val command = when (intent.action) {
            ACTION_TOGGLE -> "toggle"
            ACTION_NEXT -> "next"
            ACTION_PREVIOUS -> "previous"
            else -> return
        }
        if (PlayerWidgetBridge.send(command)) return

        // El reproductor ya no está en marcha (el sistema cerró la app y el
        // widget seguía mostrando los controles). Se repinta para que el
        // siguiente toque abra la app y se intenta abrirla ya; Android puede
        // impedir esto último desde segundo plano.
        val appContext = context.applicationContext
        PlayerWidgetState.load(appContext).copy(playing = false).save(appContext)
        val pending = goAsync()
        PlayerWidgetProvider.updateAll(appContext) { pending.finish() }
        try {
            PlayerWidgetProvider.openAppIntent(appContext).send()
        } catch (e: PendingIntent.CanceledException) {
            // Nada que hacer: el widget ya quedó listo para abrir la app.
        }
    }

    companion object {
        const val ACTION_TOGGLE = "com.carlosavellaneda.symphopk.widget.TOGGLE"
        const val ACTION_NEXT = "com.carlosavellaneda.symphopk.widget.NEXT"
        const val ACTION_PREVIOUS = "com.carlosavellaneda.symphopk.widget.PREVIOUS"
    }
}
