import 'album.dart';
import 'artist.dart';
import 'song.dart';

/// Funciones puras que derivan las vistas de la biblioteca a partir de la
/// lista de canciones. Se mantienen sin dependencias para poder testearlas.

int _byName(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());

List<Album> groupAlbums(List<Song> songs) {
  final groups = <String, List<Song>>{};
  for (final song in songs) {
    final key = song.albumId?.toString() ?? 'name:${song.album}';
    groups.putIfAbsent(key, () => []).add(song);
  }
  final albums = [
    for (final entry in groups.entries)
      Album(
        key: entry.key,
        name: entry.value.first.album,
        artist: _albumArtist(entry.value),
        songs: entry.value..sort(_byTrack),
      ),
  ];
  return albums..sort((a, b) => _byName(a.name, b.name));
}

List<Artist> groupArtists(List<Song> songs) {
  final groups = <String, List<Song>>{};
  for (final song in songs) {
    final key = song.artistId?.toString() ?? 'name:${song.artist}';
    groups.putIfAbsent(key, () => []).add(song);
  }
  final artists = [
    for (final entry in groups.entries)
      Artist(
        key: entry.key,
        name: entry.value.first.artist,
        songs: entry.value..sort((a, b) => _byName(a.title, b.title)),
        albumCount: entry.value.map((s) => s.albumId ?? s.album).toSet().length,
      ),
  ];
  return artists..sort((a, b) => _byName(a.name, b.name));
}

/// Búsqueda por título o artista, sin distinguir mayúsculas.
List<Song> searchSongs(List<Song> songs, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return songs;
  return [
    for (final song in songs)
      if (song.title.toLowerCase().contains(q) ||
          song.artist.toLowerCase().contains(q))
        song,
  ];
}

int _byTrack(Song a, Song b) {
  final byTrack = (a.track ?? 0).compareTo(b.track ?? 0);
  return byTrack != 0 ? byTrack : _byName(a.title, b.title);
}

String _albumArtist(List<Song> songs) {
  final artists = songs.map((s) => s.artist).toSet();
  return artists.length == 1 ? artists.first : 'Varios artistas';
}
