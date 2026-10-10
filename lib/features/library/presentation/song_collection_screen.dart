import 'package:flutter/material.dart';

import '../domain/song.dart';
import 'widgets/artwork_image.dart';
import 'widgets/song_tile.dart';

/// Detalle de un conjunto de canciones (álbum o artista) con su carátula.
class SongCollectionScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
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
                      songId: songs.isEmpty ? null : songs.first.id,
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
                ],
              ),
            ),
          ),
          SliverFixedExtentList.builder(
            itemExtent: 72,
            itemCount: songs.length,
            itemBuilder: (context, index) => SongTile(song: songs[index]),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ],
      ),
    );
  }
}
