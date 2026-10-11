import '../../library/domain/song.dart';
import '../domain/lyrics.dart';
import 'local_lyrics_sources.dart';
import 'lrclib_client.dart';
import 'lyrics_disk_cache.dart';

/// Resultado de buscar la letra de una canción.
sealed class LyricsResult {
  const LyricsResult();
}

class LyricsFound extends LyricsResult {
  const LyricsFound(this.lyrics);

  final Lyrics lyrics;
}

/// La canción es instrumental: no tiene letra.
class LyricsInstrumental extends LyricsResult {
  const LyricsInstrumental();
}

class LyricsNotFound extends LyricsResult {
  const LyricsNotFound();
}

/// No se pudo consultar por falta de conexión; se puede reintentar.
class LyricsOffline extends LyricsResult {
  const LyricsOffline();
}

/// El servicio falló o devolvió algo inesperado; se puede reintentar.
class LyricsUnavailable extends LyricsResult {
  const LyricsUnavailable();
}

/// Reúne todas las fuentes de letras y sus cachés.
///
/// Orden de búsqueda: memoria, archivo `.lrc`, metadatos del archivo, caché
/// en disco y, por último, LRCLIB. Solo lo descargado de LRCLIB pasa por el
/// disco, y nunca de forma permanente.
class LyricsRepository {
  LyricsRepository({
    required this._localSources,
    required this._remote,
    required LyricsDiskCache diskCache,
    bool Function()? diskCacheEnabled,
    this.memoryCapacity = 60,
  }) : _disk = diskCache,
       _diskEnabled = diskCacheEnabled ?? (() => true);

  final List<LocalLyricsSource> _localSources;
  final RemoteLyricsSource _remote;
  final LyricsDiskCache _disk;
  final bool Function() _diskEnabled;
  final int memoryCapacity;

  // Resultados definitivos de esta sesión (encontrada, instrumental o no
  // encontrada). Los fallos de red no se guardan para poder reintentar.
  final _memory = <int, LyricsResult>{};
  final _pending = <int, Future<LyricsResult>>{};

  Future<LyricsResult> lyricsFor(Song song) {
    final cached = _memory.remove(song.id);
    if (cached != null) {
      _memory[song.id] = cached; // pasa a ser la usada más recientemente
      return Future.value(cached);
    }
    // El cuerpo va entre llaves a propósito: `remove` devuelve este mismo
    // futuro y, si `whenComplete` lo recibiera, esperaría por sí mismo.
    return _pending[song.id] ??= _resolve(song).whenComplete(() {
      _pending.remove(song.id);
    });
  }

  /// Deja lista la letra de una canción que todavía no suena. Los errores
  /// se ignoran: se volverá a intentar cuando llegue su turno.
  Future<void> prefetch(Song song) async {
    try {
      await lyricsFor(song);
    } on Object {
      // Sin efecto: la precarga es solo una optimización.
    }
  }

  /// Olvida los resultados de la sesión (p. ej. tras conceder una carpeta
  /// con archivos `.lrc`).
  void clearMemory() => _memory.clear();

  Future<LyricsResult> _resolve(Song song) async {
    for (final source in _localSources) {
      final lyrics = await source.find(song);
      if (lyrics != null) return _remember(song, _toResult(lyrics));
    }

    final key = lyricsCacheKey(song);
    if (_diskEnabled()) {
      final lyrics = await _disk.read(key);
      if (lyrics != null) return _remember(song, _toResult(lyrics));
    }

    final Lyrics? lyrics;
    try {
      lyrics = await _remote.fetch(song);
    } on LyricsNetworkException {
      return const LyricsOffline();
    } on Object {
      // Error del servicio o respuesta inesperada: nunca debe propagarse
      // hasta cerrar la app.
      return const LyricsUnavailable();
    }
    if (lyrics == null) return _remember(song, const LyricsNotFound());
    if (_diskEnabled()) await _disk.write(key, lyrics);
    return _remember(song, _toResult(lyrics));
  }

  LyricsResult _toResult(Lyrics lyrics) {
    if (lyrics.instrumental) return const LyricsInstrumental();
    if (lyrics.isEmpty) return const LyricsNotFound();
    return LyricsFound(lyrics);
  }

  LyricsResult _remember(Song song, LyricsResult result) {
    _memory[song.id] = result;
    while (_memory.length > memoryCapacity) {
      _memory.remove(_memory.keys.first);
    }
    return result;
  }
}
