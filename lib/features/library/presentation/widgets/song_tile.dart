import 'package:flutter/material.dart';

import '../../../../core/utils/formatters.dart';
import '../../domain/song.dart';
import 'artwork_image.dart';

/// Fila de canción reutilizada en biblioteca, álbumes, listas y cola.
class SongTile extends StatelessWidget {
  const SongTile({
    super.key,
    required this.song,
    this.onTap,
    this.trailing,
    this.isCurrent = false,
    this.showArtwork = true,
  });

  final Song song;
  final VoidCallback? onTap;
  final Widget? trailing;

  /// Resalta la canción que está sonando.
  final bool isCurrent;
  final bool showArtwork;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListTile(
      onTap: onTap,
      leading: showArtwork ? ArtworkImage(songId: song.id, size: 48) : null,
      title: Text(
        song.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
          color: isCurrent ? scheme.primary : null,
        ),
      ),
      subtitle: Text(
        '${song.artist} · ${formatDuration(song.duration)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      trailing: trailing,
    );
  }
}
