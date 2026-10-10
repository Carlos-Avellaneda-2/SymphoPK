import 'package:flutter/foundation.dart';

import '../../library/domain/song.dart';

enum QueueRepeat { off, all, one }

/// Foto inmutable de la cola de reproducción.
@immutable
class QueueState {
  const QueueState({
    required this.songs,
    required this.index,
    required this.shuffle,
    required this.repeat,
  });

  const QueueState.empty()
    : songs = const [],
      index = -1,
      shuffle = false,
      repeat = QueueRepeat.off;

  /// Canciones en orden de reproducción (ya barajadas si procede).
  final List<Song> songs;

  /// Posición de la canción actual en [songs]; `-1` si la cola está vacía.
  final int index;
  final bool shuffle;
  final QueueRepeat repeat;

  Song? get current => index >= 0 && index < songs.length ? songs[index] : null;

  bool get isEmpty => songs.isEmpty;
}
