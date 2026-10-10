import 'package:flutter/foundation.dart';

import 'song.dart';

@immutable
class Album {
  const Album({
    required this.key,
    required this.name,
    required this.artist,
    required this.songs,
  });

  /// Clave estable de agrupación (id de MediaStore o nombre si falta).
  final String key;
  final String name;
  final String artist;

  /// Canciones ordenadas por número de pista.
  final List<Song> songs;

  /// Canción cuya carátula representa al álbum.
  Song get cover => songs.first;
}
