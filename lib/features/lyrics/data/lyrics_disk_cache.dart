import 'dart:convert';
import 'dart:io';

import '../../library/domain/song.dart';
import '../domain/lyrics.dart';

/// Caché temporal de letras en disco.
///
/// Vive en el directorio de caché de la app, que el sistema puede vaciar
/// cuando quiera: nada de lo que guarda es permanente. Además se limpia
/// sola: descarta las letras que llevan [maxAge] sin usarse y, si el total
/// supera [maxBytes], las menos usadas recientemente.
class LyricsDiskCache {
  LyricsDiskCache({
    required this._directory,
    this._clock = DateTime.now,
    this.maxBytes = 5 * 1024 * 1024,
    this.maxAge = const Duration(days: 7),
  });

  final Future<Directory> Function() _directory;
  final DateTime Function() _clock;
  final int maxBytes;
  final Duration maxAge;

  /// Letra guardada, o `null` si no está, caducó o el archivo está dañado.
  /// Leerla cuenta como uso y renueva su caducidad.
  Future<Lyrics?> read(String key) async {
    try {
      final file = await _file(key);
      if (!file.existsSync()) return null;
      if (_isExpired(file)) {
        file.deleteSync();
        return null;
      }
      final lyrics = decodeLyrics(await file.readAsString());
      if (lyrics == null) {
        file.deleteSync();
        return null;
      }
      // La fecha de modificación hace de «último uso».
      file.setLastModifiedSync(_clock());
      return lyrics;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> write(String key, Lyrics lyrics) async {
    try {
      final file = await _file(key);
      file.parent.createSync(recursive: true);
      await file.writeAsString(encodeLyrics(lyrics), flush: true);
      file.setLastModifiedSync(_clock());
      await evict();
    } on FileSystemException {
      // Sin espacio o sin permiso: la letra simplemente no se guarda.
    }
  }

  /// Aplica la caducidad y el límite de tamaño.
  Future<void> evict() async {
    try {
      final files = await _files();
      final alive = <File>[];
      for (final file in files) {
        if (_isExpired(file)) {
          file.deleteSync();
        } else {
          alive.add(file);
        }
      }
      // De la usada hace más tiempo a la más reciente.
      alive.sort(
        (a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()),
      );
      var total = alive.fold<int>(0, (sum, file) => sum + file.lengthSync());
      for (final file in alive) {
        if (total <= maxBytes) break;
        total -= file.lengthSync();
        file.deleteSync();
      }
    } on FileSystemException {
      // Otro proceso (o el sistema) borró archivos a la vez.
    }
  }

  /// Espacio ocupado, en bytes.
  Future<int> sizeBytes() async {
    try {
      final files = await _files();
      return files.fold<int>(0, (sum, file) => sum + file.lengthSync());
    } on FileSystemException {
      return 0;
    }
  }

  Future<void> clear() async {
    try {
      final directory = await _lyricsDirectory();
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    } on FileSystemException {
      // Ya no existía.
    }
  }

  bool _isExpired(File file) =>
      _clock().difference(file.lastModifiedSync()) > maxAge;

  Future<Directory> _lyricsDirectory() async =>
      Directory('${(await _directory()).path}/lyrics');

  Future<File> _file(String key) async =>
      File('${(await _lyricsDirectory()).path}/$key.json');

  Future<List<File>> _files() async {
    final directory = await _lyricsDirectory();
    if (!directory.existsSync()) return const [];
    return [
      for (final entry in directory.listSync())
        if (entry is File && entry.path.endsWith('.json')) entry,
    ];
  }
}

const String _cacheKeyVersion = 'v2';

/// Clave de caché de una canción. Se basa en sus datos y no en su id de
/// MediaStore, que puede cambiar si el sistema reindexa la biblioteca.
String lyricsCacheKey(Song song) {
  final text = [
    // Al cambiar el criterio de selección se cambia la versión, para no
    // seguir sirviendo letras elegidas con el criterio anterior.
    _cacheKeyVersion,
    song.artist,
    song.title,
    song.album,
    song.duration.inSeconds,
  ].join('\u0001').toLowerCase();
  // FNV-1a de 64 bits: suficiente para nombres de archivo sin colisiones
  // prácticas y sin añadir una dependencia de criptografía.
  var hash = 0xcbf29ce484222325;
  for (final byte in utf8.encode(text)) {
    hash ^= byte;
    hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

String encodeLyrics(Lyrics lyrics) => jsonEncode({
  'origin': lyrics.origin.name,
  'instrumental': lyrics.instrumental,
  'plain': lyrics.plainText,
  'lines': [
    for (final line in lyrics.lines) [line.time.inMilliseconds, line.text],
  ],
});

/// Devuelve `null` si [source] no es una letra válida.
Lyrics? decodeLyrics(String source) {
  try {
    final data = jsonDecode(source) as Map<String, dynamic>;
    return Lyrics(
      origin: LyricsOrigin.values.byName(data['origin'] as String),
      instrumental: data['instrumental'] as bool? ?? false,
      plainText: data['plain'] as String?,
      lines: [
        for (final line in data['lines'] as List)
          LyricLine(
            Duration(milliseconds: (line as List)[0] as int),
            line[1] as String,
          ),
      ],
    );
  } on Object {
    return null;
  }
}
