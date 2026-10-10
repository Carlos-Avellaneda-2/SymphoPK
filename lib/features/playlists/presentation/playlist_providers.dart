import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../library/domain/song.dart';
import '../../library/presentation/library_providers.dart';
import '../data/playlist_repository.dart';
import '../domain/playlist.dart';

final playlistRepositoryProvider = Provider<PlaylistRepository>(
  (ref) => DriftPlaylistRepository(ref.watch(appDatabaseProvider)),
);

final playlistsProvider = StreamProvider<List<Playlist>>(
  (ref) => ref.watch(playlistRepositoryProvider).watchAll(),
);

final playlistProvider = StreamProvider.family<Playlist?, int>(
  (ref, id) => ref.watch(playlistRepositoryProvider).watch(id),
);

/// Resuelve los ids guardados contra la biblioteca actual. Las canciones que
/// ya no existen en el dispositivo se omiten.
List<Song> resolveSongs(List<int> ids, Map<int, Song> byId) => [
  for (final id in ids) ?byId[id],
];

final playlistSongsProvider = Provider.family<List<Song>, int>((ref, id) {
  final playlist = ref.watch(playlistProvider(id)).value;
  if (playlist == null) return const [];
  return resolveSongs(playlist.songIds, ref.watch(songsByIdProvider));
});
