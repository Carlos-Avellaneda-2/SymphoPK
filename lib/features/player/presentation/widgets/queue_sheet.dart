import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/formatters.dart';
import '../../../library/presentation/widgets/song_tile.dart';
import '../player_providers.dart';

/// Muestra la cola de reproducción: tocar salta a esa canción, arrastrar
/// reordena y la «x» la quita.
Future<void> showQueueSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => const _QueueSheet(),
  );
}

class _QueueSheet extends ConsumerWidget {
  const _QueueSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final queue = ref.watch(queueStateProvider).value;
    final songs = queue?.songs ?? const [];
    final handler = ref.read(audioHandlerProvider);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: [
                Text(
                  'Cola de reproducción',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Text(
                  songCountLabel(songs.length),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              scrollController: scrollController,
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: songs.length,
              onReorderItem: handler.moveQueueItem,
              itemBuilder: (context, index) {
                final song = songs[index];
                return SongTile(
                  // La misma canción puede aparecer dos veces en la cola.
                  key: ValueKey('$index-${song.id}'),
                  song: song,
                  isCurrent: index == queue?.index,
                  onTap: () => handler.skipToQueueItem(index),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Quitar de la cola',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => handler.removeQueueItemAt(index),
                      ),
                      ReorderableDragStartListener(
                        index: index,
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(Icons.drag_handle_rounded),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
