import 'package:flutter/foundation.dart';

/// Canción de la biblioteca local. `id` es el identificador de MediaStore.
@immutable
class Song {
  const Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.uri,
    required this.duration,
    this.albumId,
    this.artistId,
    this.track,
    this.dateAdded,
    this.folder = '',
  });

  final int id;
  final String title;
  final String artist;
  final String album;

  /// URI reproducible (`content://...` en Android).
  final String uri;
  final Duration duration;
  final int? albumId;
  final int? artistId;
  final int? track;

  /// Segundos desde epoch, tal como lo entrega MediaStore.
  final int? dateAdded;

  /// Ruta absoluta de la carpeta que contiene el archivo; vacía si se
  /// desconoce.
  final String folder;

  @override
  bool operator ==(Object other) => other is Song && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Song($id, $title)';
}
