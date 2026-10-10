import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../library/presentation/widgets/artwork_image.dart';
import '../../library/presentation/widgets/empty_state.dart';
import '../../library/presentation/widgets/screen_title.dart';
import '../domain/playlist.dart';
import 'playlist_detail_screen.dart';
import 'playlist_providers.dart';
import 'widgets/playlist_dialogs.dart';

class PlaylistsScreen extends ConsumerWidget {
  const PlaylistsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ScreenTitle(
              'Listas',
              trailing: IconButton.filledTonal(
                tooltip: 'Nueva lista',
                onPressed: () => createPlaylistFlow(context, ref),
                icon: const Icon(Icons.add_rounded),
              ),
            ),
            Expanded(
              child: playlists.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => EmptyState(
                  icon: Icons.error_outline_rounded,
                  title: 'No se pudieron cargar las listas',
                  message: '$error',
                ),
                data: (all) => all.isEmpty
                    ? EmptyState(
                        icon: Icons.queue_music_rounded,
                        title: 'Crea tu primera lista',
                        message: 'Agrupa tus canciones como quieras.',
                        actionLabel: 'Nueva lista',
                        onAction: () => createPlaylistFlow(context, ref),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 16),
                        itemCount: all.length,
                        itemExtent: 72,
                        itemBuilder: (context, index) =>
                            _PlaylistTile(playlist: all[index]),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaylistTile extends ConsumerWidget {
  const _PlaylistTile({required this.playlist});

  final Playlist playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // La carátula es la de la primera canción que siga en el dispositivo.
    final songs = ref.watch(playlistSongsProvider(playlist.id));
    return ListTile(
      leading: ArtworkImage(
        songId: songs.isEmpty ? null : songs.first.id,
        size: 48,
      ),
      title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(songCountLabel(playlist.songIds.length)),
      trailing: PopupMenuButton<VoidCallback>(
        tooltip: 'Opciones de la lista',
        onSelected: (action) => action(),
        itemBuilder: (_) => [
          PopupMenuItem(
            value: () => renamePlaylistFlow(context, ref, playlist),
            child: const Text('Renombrar'),
          ),
          PopupMenuItem(
            value: () => deletePlaylistFlow(context, ref, playlist),
            child: const Text('Eliminar'),
          ),
        ],
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PlaylistDetailScreen(playlistId: playlist.id),
        ),
      ),
    );
  }
}
