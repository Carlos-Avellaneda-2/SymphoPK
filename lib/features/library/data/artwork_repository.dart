import 'dart:typed_data';

import 'library_scanner.dart';

/// Caché LRU en memoria de carátulas. Evita volver a consultar MediaStore
/// al hacer scroll y permite pintar de forma síncrona lo ya cargado.
class ArtworkRepository {
  ArtworkRepository(this._scanner, {this.capacity = 300});

  final LibraryScanner _scanner;
  final int capacity;

  // El mapa literal conserva el orden de inserción: el primero es el más viejo.
  final _cache = <(int, int), Uint8List?>{};
  final _pending = <(int, int), Future<Uint8List?>>{};

  bool isCached(int songId, int size) => _cache.containsKey((songId, size));

  /// Carátula ya cargada, sin tocar el orden de uso.
  Uint8List? peek(int songId, int size) => _cache[(songId, size)];

  Future<Uint8List?> load(int songId, {required int size}) {
    final key = (songId, size);
    if (_cache.containsKey(key)) {
      final bytes = _cache.remove(key);
      _cache[key] = bytes; // se reinserta como el más reciente
      return Future.value(bytes);
    }
    return _pending[key] ??= _fetch(key);
  }

  Future<Uint8List?> _fetch((int, int) key) async {
    try {
      Uint8List? bytes;
      try {
        bytes = await _scanner.artwork(key.$1, size: key.$2);
      } catch (_) {
        bytes = null; // sin carátula o archivo ilegible: se usa el marcador
      }
      _cache[key] = bytes;
      while (_cache.length > capacity) {
        _cache.remove(_cache.keys.first);
      }
      return bytes;
    } finally {
      _pending.remove(key);
    }
  }
}
