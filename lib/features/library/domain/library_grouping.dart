import 'album.dart';
import 'artist.dart';
import 'folder.dart';
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

/// Construye el árbol de carpetas que contienen música, para navegarlo como
/// en un explorador de archivos.
///
/// La raíz devuelta es la primera carpeta «interesante»: se saltan los
/// niveles superiores que solo contienen otra carpeta (por ejemplo
/// `/storage/emulated/0`), de modo que se empieza directamente donde la
/// música se ramifica. Devuelve `null` si ninguna canción tiene carpeta.
Folder? buildFolderTree(List<Song> songs) {
  final root = _FolderBuilder('/');
  var any = false;
  for (final song in songs) {
    if (song.folder.isEmpty) continue;
    any = true;
    var node = root;
    for (final segment in song.folder.split('/')) {
      if (segment.isEmpty) continue;
      node = node.children.putIfAbsent(
        segment,
        () => _FolderBuilder(
          node.path == '/' ? '/$segment' : '${node.path}/$segment',
        ),
      );
    }
    node.songs.add(song);
  }
  if (!any) return null;

  var folder = root.build();
  while (folder.songs.isEmpty && folder.subfolders.length == 1) {
    folder = folder.subfolders.single;
  }
  return folder;
}

class _FolderBuilder {
  _FolderBuilder(this.path);

  final String path;
  final children = <String, _FolderBuilder>{};
  final songs = <Song>[];

  Folder build() {
    final subfolders = [for (final child in children.values) child.build()]
      ..sort((a, b) {
        final byName = _byName(a.name, b.name);
        return byName != 0 ? byName : a.path.compareTo(b.path);
      });
    final ownSongs = songs..sort((a, b) => _byName(a.title, b.title));
    return Folder(
      path: path,
      name: folderName(path),
      subfolders: List.unmodifiable(subfolders),
      songs: List.unmodifiable(ownSongs),
      allSongs: List.unmodifiable([
        ...ownSongs,
        for (final child in subfolders) ...child.allSongs,
      ]),
    );
  }
}

/// Último segmento de una ruta: `/storage/emulated/0/Music/Rock` -> `Rock`.
String folderName(String path) {
  final segments = path.split('/').where((s) => s.isNotEmpty);
  return segments.isEmpty ? path : segments.last;
}

/// Ruta abreviada para mostrarla, sin el prefijo del almacenamiento interno:
/// `/storage/emulated/0/Music/Rock` -> `Music/Rock`. Las tarjetas SD
/// conservan su identificador (`/storage/1A2B-3C4D/Music` ->
/// `1A2B-3C4D/Music`). La raíz del almacenamiento queda vacía.
String folderDisplayPath(String path) {
  final segments = path.split('/').where((s) => s.isNotEmpty).toList();
  if (segments.length >= 3 &&
      segments[0] == 'storage' &&
      segments[1] == 'emulated') {
    segments.removeRange(0, 3);
  } else if (segments.isNotEmpty && segments[0] == 'storage') {
    segments.removeAt(0);
  }
  return segments.join('/');
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
