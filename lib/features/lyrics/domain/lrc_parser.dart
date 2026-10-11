import 'lyrics.dart';

/// Resultado de analizar un texto en formato LRC.
class ParsedLrc {
  const ParsedLrc({required this.lines, required this.plainText});

  /// Líneas sincronizadas, ordenadas por tiempo y con el offset aplicado.
  /// Vacía si el texto no contiene marcas de tiempo.
  final List<LyricLine> lines;

  /// El mismo contenido sin marcas ni etiquetas, como texto corrido.
  final String plainText;

  bool get isSynced => lines.isNotEmpty;
}

// [mm:ss], [mm:ss.x], [mm:ss.xx], [mm:ss.xxx] y la variante [mm:ss:xx].
final RegExp _timeTag = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');

// Etiquetas de metadatos: [ar:Artista], [ti:Título], [offset:+250]...
final RegExp _metaTag = RegExp(r'^\[([a-zA-Z#][a-zA-Z_]*):(.*)\]$');

// Marcas por palabra del formato «LRC mejorado»: <mm:ss.xx>.
final RegExp _wordTag = RegExp(r'<\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?>');

/// Analiza un texto LRC.
///
/// Admite varias marcas de tiempo en una misma línea (la letra se repite en
/// cada una), la etiqueta `[offset:±ms]` y líneas vacías, que se conservan
/// como pausas. Las etiquetas de metadatos y las marcas por palabra se
/// descartan. El texto sin ninguna marca se devuelve solo como [plainText].
ParsedLrc parseLrc(String content) {
  final lines = <LyricLine>[];
  final plain = <String>[];
  var offset = Duration.zero;

  for (final rawLine in content.replaceAll('\r\n', '\n').split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) {
      plain.add('');
      continue;
    }

    final meta = _metaTag.firstMatch(line);
    if (meta != null && _timeTag.matchAsPrefix(line) == null) {
      if (meta.group(1)!.toLowerCase() == 'offset') {
        final millis = int.tryParse(
          meta.group(2)!.trim().replaceFirst('+', ''),
        );
        if (millis != null) offset = Duration(milliseconds: millis);
      }
      continue;
    }

    // Marcas de tiempo consecutivas al principio de la línea.
    final times = <Duration>[];
    var rest = line;
    while (true) {
      final match = _timeTag.matchAsPrefix(rest);
      if (match == null) break;
      times.add(_parseTime(match));
      rest = rest.substring(match.end).trimLeft();
    }
    final text = rest.replaceAll(_wordTag, '').trim();

    if (times.isEmpty) {
      plain.add(text);
      continue;
    }
    plain.add(text);
    for (final time in times) {
      lines.add(LyricLine(time, text));
    }
  }

  // Un offset positivo adelanta la letra, como define el formato.
  final shifted = [
    for (final line in lines)
      LyricLine(_nonNegative(line.time - offset), line.text),
  ];
  // `sort` de Dart no es estable: el índice original desempata para que dos
  // líneas con la misma marca conserven su orden en el archivo.
  final indexed =
      [for (var i = 0; i < shifted.length; i++) (index: i, line: shifted[i])]
        ..sort((a, b) {
          final byTime = a.line.time.compareTo(b.line.time);
          return byTime != 0 ? byTime : a.index.compareTo(b.index);
        });

  return ParsedLrc(
    lines: List.unmodifiable([for (final entry in indexed) entry.line]),
    plainText: _trimBlankEdges(plain).join('\n'),
  );
}

/// Convierte un texto cualquiera (LRC o letra normal) en [Lyrics]. Devuelve
/// `null` si no queda nada que mostrar.
Lyrics? lyricsFromText(String? text, LyricsOrigin origin) {
  if (text == null || text.trim().isEmpty) return null;
  final parsed = parseLrc(text);
  if (parsed.isSynced && parsed.lines.any((line) => line.text.isNotEmpty)) {
    return Lyrics(origin: origin, lines: parsed.lines);
  }
  if (parsed.plainText.trim().isEmpty) return null;
  return Lyrics(origin: origin, plainText: parsed.plainText);
}

Duration _parseTime(Match match) {
  final minutes = int.parse(match.group(1)!);
  final seconds = int.parse(match.group(2)!);
  final fraction = match.group(3);
  // «.5» son 500 ms, «.50» también y «.500» también.
  final millis = fraction == null
      ? 0
      : int.parse(fraction.padRight(3, '0').substring(0, 3));
  return Duration(minutes: minutes, seconds: seconds, milliseconds: millis);
}

Duration _nonNegative(Duration value) =>
    value.isNegative ? Duration.zero : value;

List<String> _trimBlankEdges(List<String> lines) {
  var start = 0;
  var end = lines.length;
  while (start < end && lines[start].isEmpty) {
    start++;
  }
  while (end > start && lines[end - 1].isEmpty) {
    end--;
  }
  return lines.sublist(start, end);
}
