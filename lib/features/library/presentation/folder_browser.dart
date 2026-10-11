import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../player/presentation/player_providers.dart';
import '../domain/folder.dart';
import '../domain/library_grouping.dart';
import 'library_providers.dart';
import 'widgets/artwork_image.dart';
import 'widgets/empty_state.dart';
import 'widgets/song_menu.dart';
import 'widgets/song_tile.dart';

/// Contenido de una carpeta al estilo de un explorador: primero una barra
/// con la ruta y las acciones, después las subcarpetas y por último las
/// canciones que hay directamente en ella.
class FolderContentsView extends ConsumerWidget {
  const FolderContentsView({super.key, required this.folder});

  final Folder folder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentId = ref.watch(currentSongProvider.select((s) => s?.id));
    final handler = ref.read(audioHandlerProvider);
    final subfolders = folder.subfolders;
    final songs = folder.songs;

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: 1 + subfolders.length + songs.length,
      itemBuilder: (context, index) {
        if (index == 0) return _FolderBar(folder: folder);
        final folderIndex = index - 1;
        if (folderIndex < subfolders.length) {
          return _FolderTile(folder: subfolders[folderIndex]);
        }
        final songIndex = folderIndex - subfolders.length;
        final song = songs[songIndex];
        return SongTile(
          song: song,
          isCurrent: song.id == currentId,
          // Tocar una canción reproduce las de esta carpeta, sin subcarpetas.
          onTap: () => handler.playSongs(songs, index: songIndex),
          trailing: SongMenuButton(song: song),
        );
      },
    );
  }
}

/// Ruta de la carpeta y botones para reproducir todo su contenido,
/// subcarpetas incluidas.
class _FolderBar extends ConsumerWidget {
  const _FolderBar({required this.folder});

  final Folder folder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final handler = ref.read(audioHandlerProvider);
    final all = folder.allSongs;
    final displayPath = folderDisplayPath(folder.path);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
      child: Row(
        children: [
          Icon(Icons.folder_open_rounded, size: 20, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayPath.isEmpty ? 'Almacenamiento interno' : displayPath,
                  maxLines: 1,
                  // La parte final de la ruta es la que más interesa.
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: theme.textTheme.labelLarge,
                ),
                Text(
                  songCountLabel(all.length),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Reproducir en aleatorio',
            onPressed: all.isEmpty
                ? null
                : () => handler.playSongs(all, shuffle: true),
            icon: const Icon(Icons.shuffle_rounded),
          ),
          IconButton.filledTonal(
            tooltip: 'Reproducir todo',
            onPressed: all.isEmpty
                ? null
                : () => handler.playSongs(all, shuffle: false),
            icon: const Icon(Icons.play_arrow_rounded),
          ),
        ],
      ),
    );
  }
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({required this.folder});

  final Folder folder;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final folders = folder.subfolders.length;
    final subtitle = [
      if (folders == 1) '1 carpeta' else if (folders > 1) '$folders carpetas',
      songCountLabel(folder.allSongs.length),
    ].join(' · ');

    return ListTile(
      leading: Stack(
        alignment: Alignment.bottomRight,
        children: [
          ArtworkImage(songId: folder.cover?.id, size: 48),
          // Distintivo para diferenciarla de una canción.
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                bottomRight: Radius.circular(8),
              ),
            ),
            child: Icon(Icons.folder_rounded, size: 16, color: scheme.primary),
          ),
        ],
      ),
      title: Text(folder.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: scheme.onSurfaceVariant),
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: scheme.outline),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => FolderScreen(path: folder.path),
        ),
      ),
    );
  }
}

/// Pantalla de una subcarpeta. Recibe la ruta y no el objeto para reflejar
/// los cambios si la biblioteca se vuelve a escanear.
class FolderScreen extends ConsumerWidget {
  const FolderScreen({super.key, required this.path});

  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folder = ref.watch(folderProvider(path));
    return Scaffold(
      appBar: AppBar(title: Text(folder?.name ?? folderName(path))),
      body: folder == null
          ? const EmptyState(
              icon: Icons.folder_off_outlined,
              title: 'Carpeta no disponible',
              message: 'Ya no contiene música o se movió de sitio.',
            )
          : FolderContentsView(folder: folder),
    );
  }
}
