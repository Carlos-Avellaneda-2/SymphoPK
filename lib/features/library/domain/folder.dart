import 'package:flutter/foundation.dart';

import 'song.dart';

/// Carpeta del dispositivo dentro del árbol de música: puede contener
/// subcarpetas, canciones o ambas cosas.
@immutable
class Folder {
  const Folder({
    required this.path,
    required this.name,
    required this.subfolders,
    required this.songs,
    required this.allSongs,
  });

  /// Ruta absoluta; `/` para la raíz del sistema de archivos.
  final String path;

  /// Último segmento de la ruta, p. ej. `Rock`.
  final String name;

  /// Subcarpetas que contienen música (directa o más adentro), por nombre.
  final List<Folder> subfolders;

  /// Canciones situadas directamente en esta carpeta, por título.
  final List<Song> songs;

  /// Todas las canciones del subárbol: primero las propias y después las de
  /// cada subcarpeta, en el orden en que se muestran.
  final List<Song> allSongs;

  /// Canción cuya carátula representa a la carpeta.
  Song? get cover => allSongs.isEmpty ? null : allSongs.first;

  /// Busca en el subárbol la carpeta con esa ruta.
  Folder? find(String target) {
    if (target == path) return this;
    for (final child in subfolders) {
      if (target == child.path || target.startsWith('${child.path}/')) {
        return child.find(target);
      }
    }
    return null;
  }
}
