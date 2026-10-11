import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../library/domain/song.dart';
import '../../player/domain/queue_state.dart';
import '../../player/presentation/player_providers.dart';
import '../../settings/data/app_preferences.dart';
import '../data/local_lyrics_sources.dart';
import '../data/lrclib_client.dart';
import '../data/lyrics_disk_cache.dart';
import '../data/lyrics_folder_access.dart';
import '../data/lyrics_repository.dart';
import '../domain/lyrics.dart';

final lyricsFolderAccessProvider = Provider<LyricsFolderAccess>(
  (ref) => LyricsFolderAccess(),
);

/// Caché temporal en el directorio de caché de la app.
final lyricsDiskCacheProvider = Provider<LyricsDiskCache>(
  (ref) => LyricsDiskCache(directory: getTemporaryDirectory),
);

final lyricsRepositoryProvider = Provider<LyricsRepository>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return LyricsRepository(
    // El .lrc lo puso el usuario a propósito: va antes que cualquier otra.
    localSources: [
      LrcFileLyricsSource(ref.watch(lyricsFolderAccessProvider).readFile),
    ],
    // La letra incrustada suele ser texto sin tiempos: solo si LRCLIB no
    // ofrece nada mejor.
    fallbackSources: [EmbeddedLyricsSource()],
    remote: LrclibClient(client),
    diskCache: ref.watch(lyricsDiskCacheProvider),
    // Se consulta en cada uso para respetar «No guardar letras» al instante.
    diskCacheEnabled: () => ref.read(preferencesProvider).saveLyricsToDisk,
  );
});

/// Letra de la canción actual; `null` si no hay canción.
final currentLyricsProvider = FutureProvider<LyricsResult?>((ref) async {
  final song = ref.watch(currentSongProvider);
  if (song == null) return null;
  return ref.watch(lyricsRepositoryProvider).lyricsFor(song);
});

/// Línea de la letra sincronizada que corresponde a la posición actual, o
/// `-1` si aún no empezó o la letra no está sincronizada. Solo notifica al
/// cambiar de línea, no en cada actualización de la posición.
final currentLyricIndexProvider = Provider<int>((ref) {
  final result = ref.watch(currentLyricsProvider).value;
  if (result is! LyricsFound || !result.lyrics.isSynced) return -1;
  final position = ref.watch(positionProvider).value ?? Duration.zero;
  return currentLineIndex(result.lyrics.lines, position);
});

/// Canción que sonará después de la actual, si se puede saber.
final nextSongProvider = Provider<Song?>((ref) {
  final queue = ref.watch(queueStateProvider).value;
  if (queue == null || queue.isEmpty) return null;
  final next = queue.index + 1;
  if (next < queue.songs.length) return queue.songs[next];
  return queue.repeat == QueueRepeat.all ? queue.songs.first : null;
});

/// Mientras alguien lo escucha (el panel de letras), precarga la letra de la
/// siguiente canción para que aparezca sin espera al cambiar.
final lyricsPrefetchProvider = Provider.autoDispose<void>((ref) {
  final next = ref.watch(nextSongProvider);
  if (next != null) {
    unawaited(ref.watch(lyricsRepositoryProvider).prefetch(next));
  }
});
