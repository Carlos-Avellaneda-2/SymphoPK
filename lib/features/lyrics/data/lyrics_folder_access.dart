import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Carpeta a la que el usuario ha dado acceso para leer archivos `.lrc`.
@immutable
class LyricsFolder {
  const LyricsFolder({required this.uri, required this.path});

  /// Identificador del permiso concedido (URI del árbol de documentos).
  final String uri;

  /// Ruta absoluta equivalente, para mostrarla.
  final String path;
}

/// Acceso a archivos que no son multimedia.
///
/// Desde Android 11 el permiso de audio no permite leer un `.lrc`, aunque
/// esté junto a la canción. La solución es que el usuario elija una vez la
/// carpeta de su música con el selector del sistema; el permiso queda
/// guardado y se limita a esa carpeta.
class LyricsFolderAccess {
  LyricsFolderAccess({MethodChannel? channel})
    : _channel =
          channel ??
          const MethodChannel('com.carlosavellaneda.symphopk/media_library');

  final MethodChannel _channel;

  /// Lee un archivo por su ruta, directamente o a través de una carpeta
  /// concedida. Devuelve `null` si no existe o no hay acceso.
  Future<Uint8List?> readFile(String path) async {
    try {
      return await _channel.invokeMethod<Uint8List>('readFile', {'path': path});
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<List<LyricsFolder>> folders() async {
    try {
      final rows = await _channel.invokeListMethod<Map<Object?, Object?>>(
        'lyricsFolders',
      );
      return [
        for (final row in rows ?? const <Map<Object?, Object?>>[])
          LyricsFolder(
            uri: row['uri'] as String,
            path: row['path'] as String? ?? '',
          ),
      ];
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  /// Abre el selector de carpetas del sistema. Devuelve `true` si el
  /// usuario concedió una carpeta.
  Future<bool> pickFolder() async {
    try {
      return await _channel.invokeMethod<bool>('pickLyricsFolder') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> releaseFolder(String uri) async {
    try {
      await _channel.invokeMethod<void>('releaseLyricsFolder', {'uri': uri});
    } on PlatformException {
      // El permiso ya no existía.
    } on MissingPluginException {
      // Plataforma sin soporte.
    }
  }
}
