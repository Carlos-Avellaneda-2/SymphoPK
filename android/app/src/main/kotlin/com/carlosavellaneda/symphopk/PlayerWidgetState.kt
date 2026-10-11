package com.carlosavellaneda.symphopk

import android.content.Context

/**
 * Último estado conocido del reproductor. Se guarda en preferencias para
 * poder pintar los widgets tras reiniciar el teléfono o el lanzador.
 */
data class PlayerWidgetState(
    val songId: Long,
    val title: String,
    val artist: String,
    val playing: Boolean,
) {
    val hasSong: Boolean
        get() = songId != NO_SONG

    fun save(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putLong(KEY_SONG_ID, songId)
            .putString(KEY_TITLE, title)
            .putString(KEY_ARTIST, artist)
            .putBoolean(KEY_PLAYING, playing)
            .apply()
    }

    companion object {
        const val NO_SONG = -1L

        private const val PREFS = "player_widget"
        private const val KEY_SONG_ID = "song_id"
        private const val KEY_TITLE = "title"
        private const val KEY_ARTIST = "artist"
        private const val KEY_PLAYING = "playing"

        fun load(context: Context): PlayerWidgetState {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            return PlayerWidgetState(
                songId = prefs.getLong(KEY_SONG_ID, NO_SONG),
                title = prefs.getString(KEY_TITLE, "").orEmpty(),
                artist = prefs.getString(KEY_ARTIST, "").orEmpty(),
                playing = prefs.getBoolean(KEY_PLAYING, false),
            )
        }
    }
}
