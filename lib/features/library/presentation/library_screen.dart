import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../domain/album.dart';
import '../domain/artist.dart';
import '../../player/presentation/player_providers.dart';
import '../domain/song.dart';
import 'library_providers.dart';
import 'song_collection_screen.dart';
import 'widgets/artwork_image.dart';
import 'widgets/empty_state.dart';
import 'widgets/song_menu.dart';
import 'widgets/song_tile.dart';

/// Biblioteca: buscador y pestañas de canciones, álbumes y artistas.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final songs = ref.watch(songsProvider);
    final query = ref.watch(searchQueryProvider);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Text(
                  'Biblioteca',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SearchBar(
                  controller: _searchController,
                  hintText: 'Buscar por título o artista',
                  elevation: const WidgetStatePropertyAll(0),
                  leading: const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(Icons.search_rounded),
                  ),
                  trailing: [
                    if (query.isNotEmpty)
                      IconButton(
                        tooltip: 'Borrar búsqueda',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _searchController.clear();
                          ref.read(searchQueryProvider.notifier).set('');
                        },
                      ),
                  ],
                  onChanged: ref.read(searchQueryProvider.notifier).set,
                ),
              ),
              const SizedBox(height: 8),
              if (query.trim().isEmpty)
                const TabBar(
                  tabs: [
                    Tab(text: 'Canciones'),
                    Tab(text: 'Álbumes'),
                    Tab(text: 'Artistas'),
                  ],
                ),
              Expanded(
                child: songs.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => EmptyState(
                    icon: Icons.error_outline_rounded,
                    title: 'No se pudo leer la biblioteca',
                    message: '$error',
                    actionLabel: 'Reintentar',
                    onAction: () => ref.invalidate(songsProvider),
                  ),
                  data: (all) {
                    if (all.isEmpty) {
                      return EmptyState(
                        icon: Icons.music_off_rounded,
                        title: 'No hay música en el dispositivo',
                        message:
                            'Copia archivos de audio a tu teléfono y vuelve '
                            'a escanear.',
                        actionLabel: 'Volver a escanear',
                        onAction: () => ref.invalidate(songsProvider),
                      );
                    }
                    if (query.trim().isNotEmpty) {
                      return _SearchResults(
                        results: ref.watch(searchResultsProvider),
                      );
                    }
                    return TabBarView(
                      children: [
                        RefreshIndicator(
                          onRefresh: () => ref.refresh(songsProvider.future),
                          child: SongListView(songs: all),
                        ),
                        _AlbumsGrid(albums: ref.watch(albumsProvider)),
                        _ArtistsList(artists: ref.watch(artistsProvider)),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lista de canciones; al tocar una se reproduce la lista desde ese punto.
class SongListView extends ConsumerWidget {
  const SongListView({super.key, required this.songs});

  final List<Song> songs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentId = ref.watch(currentSongProvider.select((s) => s?.id));
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 4, bottom: 16),
      itemCount: songs.length,
      itemExtent: 72,
      itemBuilder: (context, index) => SongTile(
        song: songs[index],
        isCurrent: songs[index].id == currentId,
        onTap: () =>
            ref.read(audioHandlerProvider).playSongs(songs, index: index),
        trailing: SongMenuButton(song: songs[index]),
      ),
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({required this.results});

  final List<Song> results;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return const EmptyState(
        icon: Icons.search_off_rounded,
        title: 'Sin resultados',
        message: 'Prueba con otro título o artista.',
      );
    }
    return SongListView(songs: results);
  }
}

class _AlbumsGrid extends StatelessWidget {
  const _AlbumsGrid({required this.albums});

  final List<Album> albums;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.76,
      ),
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final album = albums[index];
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => SongCollectionScreen(
                title: album.name,
                subtitle:
                    '${album.artist} · ${songCountLabel(album.songs.length)}',
                songs: album.songs,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ArtworkImage(songId: album.cover.id, radius: 16, resolution: 400),
              const SizedBox(height: 8),
              Text(
                album.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                album.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ArtistsList extends StatelessWidget {
  const _ArtistsList({required this.artists});

  final List<Artist> artists;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 16),
      itemCount: artists.length,
      itemExtent: 72,
      itemBuilder: (context, index) {
        final artist = artists[index];
        final albums = artist.albumCount == 1
            ? '1 álbum'
            : '${artist.albumCount} álbumes';
        return ListTile(
          leading: ArtworkImage(songId: artist.cover.id, size: 48, radius: 24),
          title: Text(
            artist.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '$albums · ${songCountLabel(artist.songs.length)}',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => SongCollectionScreen(
                title: artist.name,
                subtitle: '$albums · ${songCountLabel(artist.songs.length)}',
                songs: artist.songs,
              ),
            ),
          ),
        );
      },
    );
  }
}
