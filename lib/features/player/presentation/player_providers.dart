import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/domain/song.dart';
import '../data/sympho_audio_handler.dart';
import '../domain/queue_state.dart';

/// Servicio de audio. Se crea en `main()` y se inyecta con un override.
final audioHandlerProvider = Provider<SymphoAudioHandler>(
  (ref) => throw UnimplementedError('audioHandlerProvider sin override'),
);

final queueStateProvider = StreamProvider<QueueState>(
  (ref) => ref.watch(audioHandlerProvider).queueState,
);

/// Canción que suena (o está en pausa); `null` si no hay cola.
final currentSongProvider = Provider<Song?>(
  (ref) => ref.watch(queueStateProvider).value?.current,
);

final isPlayingProvider = StreamProvider<bool>(
  (ref) => ref
      .watch(audioHandlerProvider)
      .playbackState
      .map((state) => state.playing)
      .distinct(),
);

final positionProvider = StreamProvider<Duration>(
  (ref) => ref.watch(audioHandlerProvider).positionStream,
);
