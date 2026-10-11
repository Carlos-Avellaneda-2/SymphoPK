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

    // 1) Coincidencia exacta. Necesita el artista; sin él solo cabe buscar.
    if (artist != null) {
      final exact = await _get('/api/get', {
        'track_name': song.title,
        'artist_name': artist,
        'album_name': ?album,
        if (song.duration > Duration.zero)
          'duration': '${song.duration.inSeconds}',
      });
      if (exact != null) {
        final lyrics = _decode(() => LrclibRecord.fromJson(jsonDecode(exact)))
            .toLyrics();
        if (lyrics != null) return lyrics;
      }
    }

    // 2) Búsqueda: se elige el resultado de duración más parecida.
    final found = await _get('/api/search', {
      'track_name': song.title,
      'artist_name': ?artist,
    });
    if (found == null) return null;
    final records = _decode(() {
      final list = jsonDecode(found);
      if (list is! List) throw const FormatException('Se esperaba una lista');
      return [for (final item in list) LrclibRecord.fromJson(item)];
    });
    return selectBestMatch(records, song.duration)?.toLyrics();
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
