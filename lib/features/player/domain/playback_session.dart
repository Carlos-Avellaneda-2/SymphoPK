import 'package:flutter/foundation.dart';

import '../../library/domain/song.dart';
import 'queue_state.dart';

/// Lo necesario para retomar la reproducción al reabrir la app. Guarda ids
/// de MediaStore, no canciones: la biblioteca se vuelve a leer en cada
/// arranque.
@immutable
class PlaybackSession {
  const PlaybackSession({
    required this.originalIds,
    required this.orderIds,
    required this.index,
    required this.shuffle,
    required this.repeat,
    this.position = Duration.zero,
  });

  /// Cola en su orden original (sin barajar).
  final List<int> originalIds;

  /// Cola en orden de reproducción.
  final List<int> orderIds;

  /// Posición de la canción actual dentro de [orderIds].
  final int index;
  final bool shuffle;
  final QueueRepeat repeat;
  final Duration position;

  PlaybackSession withPosition(Duration position) => PlaybackSession(
    originalIds: originalIds,
    orderIds: orderIds,
    index: index,
    shuffle: shuffle,
    repeat: repeat,
    position: position,
  );
}

/// Sesión con los ids ya convertidos en canciones de la biblioteca actual.
typedef ResolvedSession = ({
  List<Song> original,
  List<Song> order,
  int index,
  Duration position,
});

/// Convierte una sesión guardada en canciones reales. Las que ya no existen
/// en el dispositivo se descartan y el índice se recalcula; si la que sonaba
/// desapareció se empieza desde el inicio de la que ocupa su lugar.
/// Devuelve `null` si no queda nada que restaurar.
ResolvedSession? resolveSession(PlaybackSession session, Map<int, Song> byId) {
  final order = [for (final id in session.orderIds) ?byId[id]];
  if (order.isEmpty) return null;
  final original = [for (final id in session.originalIds) ?byId[id]];

  final savedIndex = session.index.clamp(0, session.orderIds.length - 1);
  final survivorsBefore = session.orderIds
      .take(savedIndex)
      .where(byId.containsKey)
      .length;
  final currentSurvives = byId.containsKey(session.orderIds[savedIndex]);

  return (
    original: original,
    order: order,
    index: survivorsBefore.clamp(0, order.length - 1),
    position: currentSurvives ? session.position : Duration.zero,
  );
}
