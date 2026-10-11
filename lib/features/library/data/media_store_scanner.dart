import 'package:flutter/services.dart';

import '../domain/song.dart';
import 'library_scanner.dart';

/// Lee la biblioteca desde MediaStore a través de un canal nativo propio
/// (`MediaLibraryChannel.kt`). Solo requiere el permiso de lectura de audio.
class MediaStoreScanner implements LibraryScanner {
  MediaStoreScanner({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName =
      'com.carlosavellaneda.symphopk/media_library';

  /// Descarta clips muy cortos (notas de voz, efectos).
  static const Duration minDuration = Duration(seconds: 20);

  final MethodChannel _channel;

  @override
  Future<List<Song>> scanSongs() async {
    final rows = await _channel.invokeListMethod<Map<Object?, Object?>>(
      'querySongs',
    );
    return [
      for (final row in rows ?? const <Map<Object?, Object?>>[])
        if (songFromRow(row) case final song? when song.duration >= minDuration)
          song,
    ];
  }

  @override
  Future<Uint8List?> artwork(int songId, {int size = 600}) async {
    final bytes = await _channel.invokeMethod<Uint8List>('artwork', {
      'id': songId,
      'size': size,
    });
    return (bytes == null || bytes.isEmpty) ? null : bytes;
  }

  /// Convierte una fila de MediaStore en [Song], normalizando los valores
  /// vacíos o desconocidos. Devuelve `null` si la fila no es utilizable.
  static Song? songFromRow(Map<Object?, Object?> row) {
    final id = (row['id'] as num?)?.toInt();
    final uri = row['uri'] as String?;
    if (id == null || uri == null) return null;

    String? text(String key) {
      final value = (row[key] as String?)?.trim();
      // MediaStore usa "<unknown>" cuando el archivo no trae la etiqueta.
      return (value == null || value.isEmpty || value == '<unknown>')
          ? null
          : value;
    }

    final displayName = text('displayName');
    final dot = displayName?.lastIndexOf('.') ?? -1;
    final nameWithoutExtension = dot > 0
        ? displayName!.substring(0, dot)
        : displayName;

    return Song(
      id: id,
      uri: uri,
      title: text('title') ?? nameWithoutExtension ?? 'Sin título',
      artist: text('artist') ?? 'Artista desconocido',
      album: text('album') ?? 'Álbum desconocido',
      duration: Duration(
        milliseconds: (row['durationMs'] as num?)?.toInt() ?? 0,
      ),
      albumId: (row['albumId'] as num?)?.toInt(),
      artistId: (row['artistId'] as num?)?.toInt(),
      track: (row['track'] as num?)?.toInt(),
      dateAdded: (row['dateAdded'] as num?)?.toInt(),
      folder: _folderOf(row['path'] as String?),
      path: row['path'] as String? ?? '',
    );
  }

  /// Carpeta que contiene el archivo: todo lo anterior a la última `/`.
  static String _folderOf(String? filePath) {
    if (filePath == null) return '';
    final slash = filePath.lastIndexOf('/');
    return slash <= 0 ? '' : filePath.substring(0, slash);
  }
}
