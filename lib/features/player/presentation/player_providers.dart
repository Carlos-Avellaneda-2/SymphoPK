import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../library/domain/song.dart';
import '../../library/presentation/library_providers.dart';
import '../data/playback_session_store.dart';
import '../data/playback_session_sync.dart';
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

final playbackSessionStoreProvider = Provider<PlaybackSessionStore>(
  (ref) => DriftPlaybackSessionStore(ref.watch(appDatabaseProvider)),
);

/// Restaura la última sesión cuando la biblioteca termina de escanearse y
/// la mantiene guardada mientras alguien escuche este provider.
final playbackSessionProvider = FutureProvider<void>((ref) async {
  final sync = PlaybackSessionSync(
    ref.watch(audioHandlerProvider),
    ref.watch(playbackSessionStoreProvider),
  );
  ref.onDispose(sync.dispose);
  final songs = await ref.watch(songsProvider.future);
  await sync.restoreAndStart({for (final song in songs) song.id: song});
});

final positionProvider = StreamProvider<Duration>(
  (ref) => ref.watch(audioHandlerProvider).positionStream,
);
