import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

import '../../library/domain/song.dart';
import '../domain/lrc_parser.dart';
import '../domain/lyrics.dart';

/// Fuente de letras que no necesita red.
abstract interface class LocalLyricsSource {
  /// Letra de [song], o `null` si esta fuente no tiene ninguna. No lanza:
  /// un archivo ilegible equivale a no tener letra.
  Future<Lyrics?> find(Song song);
}

/// Lee los bytes de un archivo del dispositivo, o `null` si no existe o no
/// se puede acceder a él.
typedef FileBytesReader = Future<Uint8List?> Function(String path);

/// Archivo `.lrc` junto a la canción y con su mismo nombre:
/// `Music/Rock/tema.mp3` -> `Music/Rock/tema.lrc`.
class LrcFileLyricsSource implements LocalLyricsSource {
  LrcFileLyricsSource(this._readFile);

  final FileBytesReader _readFile;

  @override
  Future<Lyrics?> find(Song song) async {
    final path = lrcPathFor(song.path);
    if (path == null) return null;
    try {
      final bytes = await _readFile(path);
      if (bytes == null || bytes.isEmpty) return null;
      return lyricsFromText(decodeLyricsBytes(bytes), LyricsOrigin.lrcFile);
    } on Object {
      return null;
    }
  }
}

/// Ruta del `.lrc` que acompaña a un archivo de audio, o `null` si la ruta
/// no sirve.
String? lrcPathFor(String audioPath) {
  if (audioPath.isEmpty) return null;
  final slash = audioPath.lastIndexOf('/');
  final dot = audioPath.lastIndexOf('.');
  // Sin extensión (o el punto pertenece a una carpeta) se añade al final.
  final base = dot > slash + 1 ? audioPath.substring(0, dot) : audioPath;
  return '$base.lrc';
}

/// Decodifica un `.lrc`: UTF-8 (con o sin BOM), UTF-16 con BOM y, si no es
/// UTF-8 válido, Latin-1, habitual en archivos antiguos.
String decodeLyricsBytes(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3), allowMalformed: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return _decodeUtf16(bytes.sublist(2), Endian.little);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return _decodeUtf16(bytes.sublist(2), Endian.big);
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return latin1.decode(bytes);
  }
}

String _decodeUtf16(Uint8List bytes, Endian endian) {
  final data = ByteData.sublistView(bytes);
  return String.fromCharCodes([
    for (var i = 0; i + 1 < bytes.length; i += 2) data.getUint16(i, endian),
  ]);
}

/// Lee la letra guardada en los metadatos de un archivo de audio.
typedef EmbeddedLyricsReader = Future<String?> Function(String path);

/// Letra incrustada en las etiquetas del archivo (ID3, Vorbis, MP4...).
class EmbeddedLyricsSource implements LocalLyricsSource {
  EmbeddedLyricsSource({EmbeddedLyricsReader? reader})
    : _read = reader ?? readEmbeddedLyrics;

  final EmbeddedLyricsReader _read;

  @override
  Future<Lyrics?> find(Song song) async {
    if (song.path.isEmpty) return null;
    try {
      return lyricsFromText(await _read(song.path), LyricsOrigin.embedded);
    } on Object {
      return null;
    }
  }
}

/// Lee las etiquetas con `audio_metadata_reader` en un isolate aparte:
/// analizar el archivo es síncrono y bloquearía la interfaz.
Future<String?> readEmbeddedLyrics(String path) {
  return Isolate.run(() {
    try {
      return readMetadata(File(path)).lyrics;
    } on Object {
      return null; // formato no soportado o archivo ilegible
    }
  });
}
