import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../core/app_info.dart';
import '../../library/domain/song.dart';
import '../domain/lrclib_match.dart';
import '../domain/lyrics.dart';

/// No hay conexión o el servidor no responde a tiempo.
class LyricsNetworkException implements Exception {
  const LyricsNetworkException(this.message);

  final String message;

  @override
  String toString() => 'LyricsNetworkException: $message';
}

/// El servicio respondió, pero con un error o con datos no válidos.
class LyricsServiceException implements Exception {
  const LyricsServiceException(this.message);

  final String message;

  @override
  String toString() => 'LyricsServiceException: $message';
}

/// Fuente de letras que necesita red.
abstract interface class RemoteLyricsSource {
  /// Letra de [song], o `null` si el servicio no tiene ninguna. Lanza
  /// [LyricsNetworkException] o [LyricsServiceException] si no se pudo
  /// consultar.
  Future<Lyrics?> fetch(Song song);
}

/// Cliente de LRCLIB (https://lrclib.net). No requiere clave de API.
class LrclibClient implements RemoteLyricsSource {
  LrclibClient(
    this._http, {
    this.userAgent = AppInfo.userAgent,
    this.timeout = const Duration(seconds: 10),
  });

  static const String _host = 'lrclib.net';

  final http.Client _http;
  final String userAgent;
  final Duration timeout;

  @override
  Future<Lyrics?> fetch(Song song) async {
    final artist = song.hasKnownArtist ? song.artist : null;
    final album = song.hasKnownAlbum ? song.album : null;
    final durationKnown = song.duration > Duration.zero;
    // De una canción suele haber muchas versiones con tiempos distintos:
    // se reúnen candidatos de varias consultas y se elige por duración.
    final candidates = <LrclibRecord>[];

    LrclibRecord? best() => selectBestMatch(
      candidates,
      title: song.title,
      artist: artist,
      duration: song.duration,
    );
    bool isExact(LrclibRecord? record) =>
        record != null &&
        record.hasSyncedLyrics &&
        (!durationKnown ||
            (record.duration - song.duration).abs() <= exactMatchTolerance);

    // 1) Coincidencia directa. Necesita el artista. Ojo: el servicio admite
    //    ±2 s y devuelve *una* de las versiones que encajan, no la más
    //    cercana, así que solo se da por buena si la duración casi coincide.
    if (artist != null) {
      final body = await _get('/api/get', {
        'track_name': song.title,
        'artist_name': artist,
        'album_name': ?album,
        // Redondeada: truncarla desplazaría la búsqueda casi un segundo.
        if (durationKnown)
          'duration': '${(song.duration.inMilliseconds / 1000).round()}',
      });
      if (body != null) {
        final record = _decode(() => LrclibRecord.fromJson(jsonDecode(body)));
        if (isExact(record)) return record.toLyrics();
        candidates.add(record);
      }
    }

    // 2) Búsqueda por título y artista principal.
    final primaryArtist = artist == null
        ? null
        : splitArtists(artist).firstOrNull;
    candidates.addAll(
      await _search({'track_name': song.title, 'artist_name': ?primaryArtist}),
    );
    final afterFields = best();
    if (isExact(afterFields)) return afterFields!.toLyrics();

    // 3) Búsqueda de texto libre: cada búsqueda devuelve como mucho 20
    //    registros y esta suele traer versiones que la anterior no. Si
    //    falla, vale lo que ya se tenía.
    try {
      candidates.addAll(
        await _search({
          'q': [
            normalizeForMatch(song.title),
            if (primaryArtist != null) normalizeForMatch(primaryArtist),
          ].join(' '),
        }),
      );
    } on LyricsNetworkException {
      if (afterFields == null) rethrow;
    } on LyricsServiceException {
      if (afterFields == null) rethrow;
    }
    return best()?.toLyrics();
  }

  /// Resultados de `/api/search`; lista vacía si no hay ninguno.
  Future<List<LrclibRecord>> _search(Map<String, String> query) async {
    final body = await _get('/api/search', query);
    if (body == null) return const [];
    return _decode(() {
      final list = jsonDecode(body);
      if (list is! List) throw const FormatException('Se esperaba una lista');
      return [for (final item in list) LrclibRecord.fromJson(item)];
    });
  }

  /// Cuerpo de la respuesta, o `null` si el servicio contesta 404.
  Future<String?> _get(String path, Map<String, String> query) async {
    final http.Response response;
    try {
      response = await _http
          .get(
            Uri.https(_host, path, query),
            headers: {'User-Agent': userAgent, 'Accept': 'application/json'},
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const LyricsNetworkException('El servidor tardó demasiado');
    } on SocketException catch (error) {
      throw LyricsNetworkException(error.message);
    } on HandshakeException catch (error) {
      throw LyricsNetworkException(error.message);
    } on http.ClientException catch (error) {
      throw LyricsNetworkException(error.message);
    }
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw LyricsServiceException('Respuesta HTTP ${response.statusCode}');
    }
    // `body` asume Latin-1 si el servidor no declara la codificación.
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  T _decode<T>(T Function() parse) {
    try {
      return parse();
    } on FormatException catch (error) {
      throw LyricsServiceException('Respuesta no válida: ${error.message}');
    } on TypeError {
      throw const LyricsServiceException('Respuesta con formato inesperado');
    }
  }
}
