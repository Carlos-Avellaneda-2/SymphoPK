import 'package:symphopk/features/library/domain/song.dart';

/// Crea una canción de prueba con valores por defecto razonables.
Song song(
  int id, {
  String? title,
  String artist = 'Artista',
  String album = 'Álbum',
  int? albumId,
  int? artistId,
  int? track,
  String folder = '',
}) => Song(
  id: id,
  title: title ?? 'Canción $id',
  artist: artist,
  album: album,
  uri: 'content://media/external/audio/media/$id',
  duration: const Duration(minutes: 3),
  albumId: albumId,
  artistId: artistId,
  track: track,
  folder: folder,
);

List<Song> songs(int count) => [for (var i = 1; i <= count; i++) song(i)];
