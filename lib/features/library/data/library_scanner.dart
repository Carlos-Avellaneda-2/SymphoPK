import 'dart:typed_data';

import '../domain/song.dart';

/// Acceso a la biblioteca de audio del dispositivo. La interfaz aísla el
/// plugin concreto: cambiar de librería (o añadir iOS) solo requiere otra
/// implementación.
abstract interface class LibraryScanner {
  /// Devuelve todas las canciones del dispositivo.
  Future<List<Song>> scanSongs();

  /// Carátula embebida de la canción, o `null` si no tiene.
  Future<Uint8List?> artwork(int songId, {int size});
}
