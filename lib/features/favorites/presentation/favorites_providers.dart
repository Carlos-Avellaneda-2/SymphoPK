import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../library/domain/song.dart';
import '../../library/presentation/library_providers.dart';
import '../../playlists/presentation/playlist_providers.dart';
import '../data/favorites_repository.dart';

final favoritesRepositoryProvider = Provider<FavoritesRepository>(
  (ref) => DriftFavoritesRepository(ref.watch(appDatabaseProvider)),
);

final favoriteIdsProvider = StreamProvider<List<int>>(
  (ref) => ref.watch(favoritesRepositoryProvider).watchIds(),
);

final favoriteIdSetProvider = Provider<Set<int>>(
  (ref) => ref.watch(favoriteIdsProvider).value?.toSet() ?? const {},
);

final favoriteSongsProvider = Provider<List<Song>>(
  (ref) => resolveSongs(
    ref.watch(favoriteIdsProvider).value ?? const [],
    ref.watch(songsByIdProvider),
  ),
);
