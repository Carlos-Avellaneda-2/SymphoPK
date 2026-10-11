import 'package:flutter/foundation.dart';

import 'lrc_parser.dart';
import 'lyrics.dart';

/// Registro de una canción en LRCLIB.
@immutable
class LrclibRecord {
  const LrclibRecord({
    required this.duration,
    this.trackName = '',
    this.artistName = '',
    this.instrumental = false,
    this.plainLyrics,
    this.syncedLyrics,
  });

  final String trackName;
  final String artistName;
  final Duration duration;
  final bool instrumental;
  final String? plainLyrics;
  final String? syncedLyrics;

  bool get hasSyncedLyrics => (syncedLyrics ?? '').trim().isNotEmpty;

  bool get hasPlainLyrics => (plainLyrics ?? '').trim().isNotEmpty;

  /// Aporta algo: una letra o la certeza de que es instrumental.
  bool get isUseful => instrumental || hasSyncedLyrics || hasPlainLyrics;

  /// Lanza [FormatException] si [json] no es un registro válido.
  factory LrclibRecord.fromJson(Object? json) {
    if (json is! Map) throw const FormatException('Registro no válido');
    final duration = json['duration'];
    return LrclibRecord(
      trackName: json['trackName'] as String? ?? '',
      artistName: json['artistName'] as String? ?? '',
      duration: Duration(
        milliseconds: duration is num ? (duration * 1000).round() : 0,
      ),
      instrumental: json['instrumental'] == true,
      plainLyrics: json['plainLyrics'] as String?,
      syncedLyrics: json['syncedLyrics'] as String?,
    );
  }

  /// Letra del registro, prefiriendo la sincronizada. `null` si no aporta
  /// nada.
  Lyrics? toLyrics() {
    if (instrumental) {
      return const Lyrics(origin: LyricsOrigin.lrclib, instrumental: true);
    }
    return lyricsFromText(syncedLyrics, LyricsOrigin.lrclib) ??
        lyricsFromText(plainLyrics, LyricsOrigin.lrclib);
  }
}

/// Diferencia de duración por debajo de la cual un registro se considera la
/// misma grabación sin necesidad de comparar con más candidatos.
const Duration exactMatchTolerance = Duration(seconds: 1);

/// Elige, entre varios registros, la letra que mejor corresponde a una
/// canción por **título, artista y duración**.
///
/// De una misma canción suele haber muchas versiones (álbum, vídeo, directo,
/// con colaboración...) cuyas letras solo cambian en los tiempos, así que la
/// duración es lo que distingue la correcta:
///
/// 1. Se descartan los registros de otro título u otro artista.
/// 2. Se descartan los que difieren más de [tolerance] en duración: su letra
///    iría desincronizada.
/// 3. De los restantes se prefieren los que tienen letra sincronizada,
///    después los de solo texto y por último los instrumentales.
/// 4. Dentro de ese grupo gana el de duración más cercana y, a igualdad, el
///    que aparece antes en [records].
///
/// Si se desconoce la duración de la canción ([duration] cero) no se pueden
/// aplicar los pasos 2 y 4.
LrclibRecord? selectBestMatch(
  List<LrclibRecord> records, {
  required String title,
  String? artist,
  required Duration duration,
  Duration tolerance = const Duration(seconds: 3),
}) {
  final durationKnown = duration > Duration.zero;
  Duration distance(LrclibRecord record) => (record.duration - duration).abs();

  final candidates = [
    for (final record in records)
      if (record.isUseful &&
          titlesMatch(title, record.trackName) &&
          artistsMatch(artist, record) &&
          (!durationKnown || distance(record) <= tolerance))
        record,
  ];
  if (candidates.isEmpty) return null;

  int quality(LrclibRecord record) => record.hasSyncedLyrics
      ? 0
      : record.hasPlainLyrics
      ? 1
      : 2;

  var best = candidates.first;
  for (final record in candidates.skip(1)) {
    final byQuality = quality(record).compareTo(quality(best));
    if (byQuality < 0 ||
        (byQuality == 0 &&
            durationKnown &&
            distance(record) < distance(best))) {
      best = record;
    }
  }
  return best;
}

/// Título o artista reducido a lo comparable: minúsculas, sin acentos, sin
/// signos y sin los añadidos habituales entre paréntesis o tras un guion
/// («(feat. X)», «[Official Video]», «- Remastered 2011»).
String normalizeForMatch(String text) {
  var value = text.toLowerCase();
  value = value.replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]'), ' ');
  value = value.replaceAll(
    RegExp(
      r'\s[-–—]\s*(remaster(ed)?|live|en vivo|version|versión|edit|mono|'
      r'stereo|bonus|deluxe|single|radio|official|oficial|feat|ft)\b.*$',
    ),
    ' ',
  );
  const accents = {
    'á': 'a',
    'à': 'a',
    'ä': 'a',
    'â': 'a',
    'ã': 'a',
    'å': 'a',
    'é': 'e',
    'è': 'e',
    'ë': 'e',
    'ê': 'e',
    'í': 'i',
    'ì': 'i',
    'ï': 'i',
    'î': 'i',
    'ó': 'o',
    'ò': 'o',
    'ö': 'o',
    'ô': 'o',
    'õ': 'o',
    'ú': 'u',
    'ù': 'u',
    'ü': 'u',
    'û': 'u',
    'ñ': 'n',
    'ç': 'c',
  };
  final buffer = StringBuffer();
  for (final rune in value.runes) {
    final char = String.fromCharCode(rune);
    buffer.write(accents[char] ?? char);
  }
  return buffer
      .toString()
      // Los apóstrofos se eliminan sin dejar hueco: «don't» = «dont».
      .replaceAll(RegExp("['’`´]"), '')
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
}

/// `true` si [recordTitle] es el mismo título que [songTitle]: iguales tras
/// normalizar, o uno contiene al otro como palabras completas (habitual en
/// subidas del tipo «Artista - Título»).
bool titlesMatch(String songTitle, String recordTitle) {
  final song = normalizeForMatch(songTitle);
  final record = normalizeForMatch(recordTitle);
  if (song.isEmpty || record.isEmpty) return false;
  return song == record ||
      _containsWords(record, song) ||
      _containsWords(song, record);
}

/// `true` si el registro es del artista de la canción. Con el artista
/// desconocido ([songArtist] nulo o vacío) vale cualquiera.
///
/// Las etiquetas con varios artistas («A, B», «A & B», «A feat. B») coinciden
/// si lo hace alguno de ellos. También vale que el artista figure en el
/// título del registro, como pasa cuando quien lo subió puso su propio
/// nombre como artista.
bool artistsMatch(String? songArtist, LrclibRecord record) {
  if (songArtist == null || songArtist.trim().isEmpty) return true;
  final recordArtist = normalizeForMatch(record.artistName);
  final recordTitle = normalizeForMatch(record.trackName);
  for (final part in splitArtists(songArtist)) {
    final artist = normalizeForMatch(part);
    if (artist.isEmpty) continue;
    if (recordArtist.isNotEmpty &&
        (_containsWords(recordArtist, artist) ||
            _containsWords(artist, recordArtist))) {
      return true;
    }
    if (_containsWords(recordTitle, artist)) return true;
  }
  return false;
}

/// Separa una etiqueta con varios artistas en sus nombres.
List<String> splitArtists(String artist) => artist
    .split(
      RegExp(
        r'\s*(?:,|;|/|&|\bfeaturing\b|\bfeat\b\.?|\bft\b\.?|\bcon\b|\bx\b)\s*',
        caseSensitive: false,
      ),
    )
    .map((part) => part.trim())
    .where((part) => part.isNotEmpty)
    .toList();

/// `true` si [needle] aparece en [haystack] respetando límites de palabra
/// (ambos ya normalizados): «love» no está en «glove me not».
bool _containsWords(String haystack, String needle) {
  if (needle.isEmpty) return false;
  return ' $haystack '.contains(' $needle ');
}
