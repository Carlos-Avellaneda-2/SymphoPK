import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/artwork_repository.dart';
import '../data/library_scanner.dart';
import '../data/media_store_scanner.dart';
import '../domain/album.dart';
import '../domain/artist.dart';
import '../domain/folder.dart';
import '../domain/library_grouping.dart';
import '../domain/song.dart';

final libraryScannerProvider = Provider<LibraryScanner>(
  (ref) => MediaStoreScanner(),
);

final artworkRepositoryProvider = Provider<ArtworkRepository>(
  (ref) => ArtworkRepository(ref.watch(libraryScannerProvider)),
);

/// Todas las canciones del dispositivo. `ref.invalidate` fuerza un reescaneo.
final songsProvider = FutureProvider<List<Song>>(
  (ref) => ref.watch(libraryScannerProvider).scanSongs(),
);

/// Índice por id para resolver referencias guardadas (listas, favoritos).
final songsByIdProvider = Provider<Map<int, Song>>((ref) {
  final songs = ref.watch(songsProvider).value ?? const <Song>[];
  return {for (final song in songs) song.id: song};
});

final albumsProvider = Provider<List<Album>>(
  (ref) => groupAlbums(ref.watch(songsProvider).value ?? const []),
);

final artistsProvider = Provider<List<Artist>>(
  (ref) => groupArtists(ref.watch(songsProvider).value ?? const []),
);

/// Raíz del árbol de carpetas con música; `null` si no hay ninguna.
final folderTreeProvider = Provider<Folder?>(
  (ref) => buildFolderTree(ref.watch(songsProvider).value ?? const []),
);

/// Carpeta en una ruta concreta. Se resuelve contra el árbol actual para que
/// las pantallas abiertas reflejen un reescaneo.
final folderProvider = Provider.family<Folder?, String>(
  (ref, path) => ref.watch(folderTreeProvider)?.find(path),
);

/// Texto de búsqueda de la biblioteca.
final searchQueryProvider = NotifierProvider<SearchQuery, String>(
  SearchQuery.new,
);

class SearchQuery extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) => state = value;
}

final searchResultsProvider = Provider<List<Song>>((ref) {
  final songs = ref.watch(songsProvider).value ?? const <Song>[];
  return searchSongs(songs, ref.watch(searchQueryProvider));
});
