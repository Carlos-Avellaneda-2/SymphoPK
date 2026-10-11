import 'package:flutter/foundation.dart';

/// De dónde salió una letra.
enum LyricsOrigin {
  lrcFile('Archivo .lrc'),
  embedded('Incrustada en el archivo'),
  lrclib('LRCLIB');

  const LyricsOrigin(this.label);

  final String label;
}

/// Línea de una letra sincronizada.
@immutable
class LyricLine {
  const LyricLine(this.time, this.text);

  /// Momento de la canción en que empieza la línea.
  final Duration time;

  /// Texto; vacío en las pausas instrumentales.
  final String text;

  @override
  bool operator ==(Object other) =>
      other is LyricLine && other.time == time && other.text == text;

  @override
  int get hashCode => Object.hash(time, text);

  @override
  String toString() => 'LyricLine($time, $text)';
}

/// Letra de una canción: sincronizada ([lines]) o solo texto ([plainText]).
@immutable
class Lyrics {
  const Lyrics({
    required this.origin,
    this.lines = const [],
    this.plainText,
    this.instrumental = false,
  });

  final LyricsOrigin origin;

  /// Líneas con marca de tiempo, ordenadas. Vacía si la letra no está
  /// sincronizada.
  final List<LyricLine> lines;

  /// Letra sin marcas de tiempo, para mostrarla como texto estático.
  final String? plainText;

  /// La canción está marcada como instrumental: no tiene letra.
  final bool instrumental;

  bool get isSynced => lines.isNotEmpty;

  bool get isEmpty =>
      !instrumental && lines.isEmpty && (plainText ?? '').trim().isEmpty;
}

/// Índice de la línea que corresponde a [position]: la última cuya marca de
/// tiempo ya pasó. Devuelve `-1` antes de la primera línea.
int currentLineIndex(List<LyricLine> lines, Duration position) {
  var low = 0;
  var high = lines.length - 1;
  var result = -1;
  while (low <= high) {
    final middle = (low + high) >> 1;
    if (lines[middle].time <= position) {
      result = middle;
      low = middle + 1;
    } else {
      high = middle - 1;
    }
  }
  return result;
}
