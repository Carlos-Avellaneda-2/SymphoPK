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
/// Orden de búsqueda: memoria, fuentes prioritarias (el archivo `.lrc`, que
/// el usuario puso a propósito), LRCLIB (con su caché en disco) y, por
/// último, fuentes de reserva (la letra incrustada en el archivo).
///
/// La letra incrustada va después de LRCLIB porque casi siempre es texto sin
/// tiempos y taparía una versión sincronizada. Aun así se usa cuando aporta
/// más: si está sincronizada y la de LRCLIB no, o si LRCLIB no tiene letra
/// o no se puede consultar.
///
/// Solo lo descargado de LRCLIB pasa por el disco, y nunca de forma
/// permanente.
class LyricsRepository {
  LyricsRepository({
    required this._localSources,
    this._fallbackSources = const [],
    required this._remote,
    required LyricsDiskCache diskCache,
    bool Function()? diskCacheEnabled,
    this.memoryCapacity = 60,
  }) : _disk = diskCache,
       _diskEnabled = diskCacheEnabled ?? (() => true);

  /// Se consultan antes que la red; lo que encuentren es definitivo.
  final List<LocalLyricsSource> _localSources;

  /// Se consultan después de la red, por si mejoran su resultado.
  final List<LocalLyricsSource> _fallbackSources;
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

    // LRCLIB: primero su caché en disco y, si no está, la red.
    final key = lyricsCacheKey(song);
    Lyrics? online;
    LyricsResult? failure;
    if (_diskEnabled()) online = await _disk.read(key);
    if (online == null) {
      try {
        online = await _remote.fetch(song);
        if (online != null && _diskEnabled()) await _disk.write(key, online);
      } on LyricsNetworkException {
        failure = const LyricsOffline();
      } on Object {
        // Error del servicio o respuesta inesperada: nunca debe propagarse
        // hasta cerrar la app.
        failure = const LyricsUnavailable();
      }
    }
    // Una letra sincronizada de LRCLIB es lo mejor que se puede obtener.
    if (online != null && online.isSynced) {
      return _remember(song, LyricsFound(online));
    }

    // Sin sincronizada en línea, la letra del propio archivo puede ser
    // mejor: gana si tiene tiempos o si LRCLIB no aportó texto.
    final onlineHasText =
        online != null && !online.instrumental && !online.isEmpty;
    for (final source in _fallbackSources) {
      final lyrics = await source.find(song);
      if (lyrics == null || lyrics.isEmpty) continue;
      if (!lyrics.isSynced && onlineHasText) break;
      final result = _toResult(lyrics);
      // Si la red falló no se recuerda: al volver la conexión se intentará
      // de nuevo por si LRCLIB tiene una versión sincronizada.
      return failure == null ? _remember(song, result) : result;
    }

    if (online != null) return _remember(song, _toResult(online));
    return failure ?? _remember(song, const LyricsNotFound());
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
