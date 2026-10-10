import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../library/presentation/widgets/artwork_image.dart';
import '../player_providers.dart';
import '../player_screen.dart';
import 'player_controls.dart';

/// Etiqueta Hero compartida por la carátula del mini reproductor y la de la
/// pantalla completa.
const String artworkHeroTag = 'now-playing-artwork';

/// Reproductor compacto y persistente. Se oculta si no hay nada en la cola.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = ref.watch(currentSongProvider);
    if (song == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final handler = ref.read(audioHandlerProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        elevation: 3,
        shadowColor: Colors.black,
        child: InkWell(
          onTap: () => openPlayerScreen(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
                child: Row(
                  children: [
                    Hero(
                      tag: artworkHeroTag,
                      child: ArtworkImage(songId: song.id, size: 44),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const PlayPauseButton(),
                    IconButton(
                      tooltip: 'Siguiente',
                      onPressed: handler.skipToNext,
                      icon: const Icon(Icons.skip_next_rounded),
                    ),
                  ],
                ),
              ),
              const _MiniProgress(),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniProgress extends ConsumerWidget {
  const _MiniProgress();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = ref.watch(currentSongProvider)?.duration.inMilliseconds ?? 0;
    final position = ref.watch(positionProvider).value?.inMilliseconds ?? 0;
    return LinearProgressIndicator(
      value: total <= 0 ? 0 : (position / total).clamp(0.0, 1.0),
      minHeight: 2,
      backgroundColor: Colors.transparent,
    );
  }
}
