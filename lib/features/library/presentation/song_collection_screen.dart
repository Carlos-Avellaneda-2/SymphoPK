import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../player/presentation/player_providers.dart';
import '../domain/song.dart';
import 'widgets/artwork_image.dart';
import 'widgets/song_menu.dart';
import 'widgets/song_tile.dart';

/// Detalle de un conjunto de canciones (álbum o artista) con su carátula.
class SongCollectionScreen extends ConsumerWidget {
  const SongCollectionScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.songs,
  });

  final String title;
  final String subtitle;
  final List<Song> songs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentId = ref.watch(currentSongProvider.select((s) => s?.id));
    final handler = ref.read(audioHandlerProvider);
    return Scaffold(
      appBar: AppBar(),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: CollectionHeader(
              coverSongId: songs.isEmpty ? null : songs.first.id,
              title: title,
              subtitle: subtitle,
              onPlay: songs.isEmpty
                  ? null
                  : () => handler.playSongs(songs, shuffle: false),
              onShuffle: songs.isEmpty
                  ? null
                  : () => handler.playSongs(songs, shuffle: true),
            ),
          ),
          SliverFixedExtentList.builder(
            itemExtent: 72,
            itemCount: songs.length,
            itemBuilder: (context, index) => SongTile(
              song: songs[index],
              isCurrent: songs[index].id == currentId,
              onTap: () => handler.playSongs(songs, index: index),
              trailing: SongMenuButton(song: songs[index]),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ],
      ),
    );
  }
}

/// Cabecera con carátula grande, título y botones de reproducir / aleatorio.
class CollectionHeader extends StatelessWidget {
  const CollectionHeader({
    super.key,
    required this.coverSongId,
    required this.title,
    required this.subtitle,
    required this.onPlay,
    required this.onShuffle,
  });

  final int? coverSongId;
  final String title;
  final String subtitle;
  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Column(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: ArtworkImage(
              songId: coverSongId,
              size: 200,
              radius: 20,
              resolution: ArtworkImage.full,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onPlay,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Reproducir'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: onShuffle,
                  icon: const Icon(Icons.shuffle_rounded),
                  label: const Text('Aleatorio'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
