import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../library/presentation/song_collection_screen.dart';
import '../../library/presentation/widgets/empty_state.dart';
import '../../library/presentation/widgets/song_menu.dart';
import '../../library/presentation/widgets/song_tile.dart';
import '../../player/presentation/player_providers.dart';
import 'playlist_providers.dart';
import 'widgets/playlist_dialogs.dart';

class PlaylistDetailScreen extends ConsumerWidget {
  const PlaylistDetailScreen({super.key, required this.playlistId});

  final int playlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlist = ref.watch(playlistProvider(playlistId)).value;
    final songs = ref.watch(playlistSongsProvider(playlistId));
    final currentId = ref.watch(currentSongProvider.select((s) => s?.id));
    final handler = ref.read(audioHandlerProvider);

    if (playlist == null) {
      // Cargando, o la lista se acaba de eliminar y la ruta está cerrándose.
      return Scaffold(appBar: AppBar());
    }

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Renombrar',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => renamePlaylistFlow(context, ref, playlist),
          ),
          IconButton(
            tooltip: 'Eliminar lista',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () async {
              final navigator = Navigator.of(context);
              if (await deletePlaylistFlow(context, ref, playlist)) {
                navigator.pop();
              }
            },
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: CollectionHeader(
              coverSongId: songs.isEmpty ? null : songs.first.id,
              title: playlist.name,
              subtitle: songCountLabel(songs.length),
              onPlay: songs.isEmpty
                  ? null
                  : () => handler.playSongs(songs, shuffle: false),
              onShuffle: songs.isEmpty
                  ? null
                  : () => handler.playSongs(songs, shuffle: true),
            ),
          ),
          if (songs.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.playlist_add_rounded,
                title: 'Lista vacía',
                message:
                    'Añade canciones desde el menú «⋮» de cualquier canción.',
              ),
            )
          else
            SliverFixedExtentList.builder(
              itemExtent: 72,
              itemCount: songs.length,
              itemBuilder: (context, index) {
                final song = songs[index];
                return SongTile(
                  song: song,
                  isCurrent: song.id == currentId,
                  onTap: () => handler.playSongs(songs, index: index),
                  trailing: SongMenuButton(
                    song: song,
                    onRemove: () => ref
                        .read(playlistRepositoryProvider)
                        .removeSong(playlistId, song.id),
                  ),
                );
              },
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ],
      ),
    );
  }
}
