import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../favorites/presentation/favorites_providers.dart';
import '../../../player/presentation/player_providers.dart';
import '../../../playlists/presentation/widgets/playlist_dialogs.dart';
import '../../domain/song.dart';
import 'artwork_image.dart';
import 'quality_badge.dart';

/// Botón «más» de una canción: cola, listas y favoritos.
class SongMenuButton extends ConsumerWidget {
  const SongMenuButton({super.key, required this.song, this.onRemove});

  final Song song;

  /// Si se indica, añade la acción «Quitar de la lista».
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      tooltip: 'Más opciones',
      icon: const Icon(Icons.more_vert_rounded),
      onPressed: () => _show(context, ref),
    );
  }

  Future<void> _show(BuildContext context, WidgetRef ref) {
    final handler = ref.read(audioHandlerProvider);
    final messenger = ScaffoldMessenger.of(context);

    void notify(String message) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));

    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (sheetContext) {
        void close() => Navigator.of(sheetContext).pop();
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: ArtworkImage(songId: song.id, size: 48),
                title: Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (song.quality.label != null) ...[
                      const SizedBox(height: 4),
                      QualityBadge(quality: song.quality, compact: true),
                    ],
                  ],
                ),
              ),
              const Divider(height: 8),
              ListTile(
                leading: const Icon(Icons.playlist_play_rounded),
                title: const Text('Reproducir a continuación'),
                onTap: () {
                  close();
                  handler.playNext(song);
                  notify('Sonará a continuación');
                },
              ),
              ListTile(
                leading: const Icon(Icons.queue_rounded),
                title: const Text('Añadir a la cola'),
                onTap: () {
                  close();
                  handler.addToQueue(song);
                  notify('Añadida a la cola');
                },
              ),
              ListTile(
                leading: const Icon(Icons.playlist_add_rounded),
                title: const Text('Añadir a una lista'),
                onTap: () {
                  close();
                  showAddToPlaylistSheet(context, ref, song);
                },
              ),
              Consumer(
                builder: (_, sheetRef, _) {
                  final isFavorite = sheetRef.watch(
                    favoriteIdSetProvider.select((s) => s.contains(song.id)),
                  );
                  return ListTile(
                    leading: Icon(
                      isFavorite
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                    ),
                    title: Text(
                      isFavorite ? 'Quitar de favoritos' : 'Añadir a favoritos',
                    ),
                    onTap: () {
                      close();
                      ref.read(favoritesRepositoryProvider).toggle(song.id);
                    },
                  );
                },
              ),
              if (onRemove != null)
                ListTile(
                  leading: const Icon(Icons.remove_circle_outline_rounded),
                  title: const Text('Quitar de la lista'),
                  onTap: () {
                    close();
                    onRemove!();
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}
