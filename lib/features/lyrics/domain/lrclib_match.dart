import 'package:flutter/foundation.dart';

import 'lrc_parser.dart';
import 'lyrics.dart';

/// Registro de una canción en LRCLIB.
@immutable
class LrclibRecord {
  const LrclibRecord({
    required this.duration,
    this.instrumental = false,
    this.plainLyrics,
    this.syncedLyrics,
  });

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

/// Elige, entre los resultados de una búsqueda, el que corresponde a una
/// canción de duración [target].
///
/// Solo valen los registros útiles cuya duración difiere como mucho
/// [tolerance]: una diferencia mayor suele ser otra versión de la canción
/// (directo, remezcla) y su letra iría desincronizada. Entre los que valen
/// se prefieren los que tienen letra sincronizada y, a igualdad, el de
/// duración más cercana. Si se desconoce la duración de la canción se
/// acepta cualquiera.
LrclibRecord? selectBestMatch(
  List<LrclibRecord> records,
  Duration target, {
  Duration tolerance = const Duration(seconds: 3),
}) {
  final durationKnown = target > Duration.zero;
  Duration distance(LrclibRecord record) => (record.duration - target).abs();

  final candidates = [
    for (final record in records)
      if (record.isUseful && (!durationKnown || distance(record) <= tolerance))
        record,
  ];
  if (candidates.isEmpty) return null;

  int rank(LrclibRecord record) => record.hasSyncedLyrics ? 0 : 1;
  LrclibRecord best = candidates.first;
  for (final record in candidates.skip(1)) {
    final byRank = rank(record).compareTo(rank(best));
    if (byRank < 0 ||
        (byRank == 0 && durationKnown && distance(record) < distance(best))) {
      best = record;
    }
  }
  return best;
}
