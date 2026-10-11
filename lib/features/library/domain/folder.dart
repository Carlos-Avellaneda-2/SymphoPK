import 'package:flutter/foundation.dart';

import 'song.dart';

/// Carpeta del dispositivo que contiene canciones directamente.
@immutable
class Folder {
  const Folder({
    required this.path,
    required this.name,
    required this.location,
    required this.songs,
  });

  /// Ruta absoluta de la carpeta.
  final String path;

  /// Último segmento de la ruta, p. ej. `Rock`.
  final String name;

  /// Ruta de la carpeta que la contiene, ya abreviada para mostrarla
  /// (p. ej. `Music`); vacía si cuelga de la raíz del almacenamiento.
  final String location;

  /// Canciones ordenadas por título.
  final List<Song> songs;

  Song get cover => songs.first;
}
