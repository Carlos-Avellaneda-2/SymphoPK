import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';

import '../../library/domain/song.dart';
import '../domain/queue_manager.dart';
import '../domain/queue_state.dart';
import '../domain/replay_gain.dart';
import 'replay_gain_reader.dart';

/// Servicio de audio de la app. Une `just_audio` (reproducción) con
/// [QueueManager] (qué suena después) y publica el estado en el formato de
/// `audio_service` para la notificación, la pantalla de bloqueo y los
/// botones de auriculares.
///
/// La UI nunca toca el reproductor: solo llama a los métodos de esta clase y
/// escucha [queueState], [playbackState] y [positionStream].
class SymphoAudioHandler extends BaseAudioHandler with SeekHandler {
  SymphoAudioHandler({
    AudioPlayer? player,
    QueueManager? queueManager,
    ReplayGainReader? replayGainReader,
  }) : _player = player ?? AudioPlayer(),
       _queue = queueManager ?? QueueManager(),
       _readReplayGain = replayGainReader ?? readReplayGain {
    _subscriptions
      ..add(_player.playbackEventStream.listen((_) => _broadcastState()))
      ..add(_player.playingStream.listen((_) => _broadcastState()))
      ..add(
        _player.processingStateStream
            .where((state) => state == ProcessingState.completed)
            .listen((_) => _onCompleted()),
      );
  }

  /// Por encima de este punto, «anterior» reinicia la canción actual.
  static const Duration _restartThreshold = Duration(seconds: 3);

  final AudioPlayer _player;
  final QueueManager _queue;
  final _subscriptions = <StreamSubscription<void>>[];
  final _queueState = BehaviorSubject<QueueState>.seeded(
    const QueueState.empty(),
  );

  /// Errores de carga consecutivos, para no saltar en bucle sin fin.
  int _failures = 0;

  final ReplayGainReader _readReplayGain;
  NormalizationMode _normalization = NormalizationMode.off;

  // Valores ReplayGain ya leídos, por id de canción (`null`: sin etiquetas).
  final _replayGainCache = <int, ReplayGainInfo?>{};
  static const int _replayGainCacheSize = 200;

  /// Tiempo máximo esperando las etiquetas antes de empezar a sonar.
  static const Duration _replayGainTimeout = Duration(milliseconds: 1500);

  ValueStream<QueueState> get queueState => _queueState.stream;

  /// Cola en su orden original, sin barajar (para persistirla).
  List<Song> get originalQueue => _queue.originalOrder;

  Stream<Duration> get positionStream => _player.positionStream;

  Duration get position => _player.position;

  /// Declara la app como reproductor de música ante el sistema. Con esta
  /// configuración `just_audio` pausa en llamadas, baja el volumen ante
  /// avisos breves y pausa al desconectar los auriculares.
  Future<void> configureAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  }

  // ---------------------------------------------------------------------
  // Cola
  // ---------------------------------------------------------------------

  /// Reemplaza la cola por [songs] y empieza a reproducir en [index].
  Future<void> playSongs(
    List<Song> songs, {
    int index = 0,
    bool? shuffle,
  }) async {
    if (songs.isEmpty) return;
    if (shuffle != null) _queue.setShuffle(shuffle);
    _queue.setQueue(songs, startIndex: index);
    await _loadCurrent();
  }

  /// Restaura una sesión guardada sin empezar a reproducir.
  Future<void> restoreSession({
    required List<Song> original,
    required List<Song> order,
    required int index,
    required bool shuffle,
    required QueueRepeat repeat,
    Duration position = Duration.zero,
  }) async {
    _queue.restore(
      original: original,
      order: order,
      index: index,
      shuffle: shuffle,
      repeat: repeat,
    );
    await _loadCurrent(position: position, autoPlay: false);
  }

  Future<void> addToQueue(Song song) async {
    final wasEmpty = _queue.isEmpty;
    _queue.add(song);
    if (wasEmpty) {
      await _loadCurrent(autoPlay: false);
    } else {
      _publishQueue();
    }
  }

  Future<void> playNext(Song song) async {
    final wasEmpty = _queue.isEmpty;
    _queue.insertNext(song);
    if (wasEmpty) {
      await _loadCurrent(autoPlay: false);
    } else {
      _publishQueue();
    }
  }

  void moveQueueItem(int from, int to) {
    _queue.move(from, to);
    _publishQueue();
  }

  @override
  Future<void> removeQueueItemAt(int index) async {
    final wasCurrent = _queue.removeAt(index);
    if (wasCurrent) {
      await _loadCurrent(autoPlay: _player.playing);
    } else {
      _publishQueue();
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (_queue.jumpTo(index) != null) await _loadCurrent();
  }

  // ---------------------------------------------------------------------
  // Transporte
  // ---------------------------------------------------------------------

  @override
  Future<void> play() async {
    if (_queue.current == null) return;
    // Tras terminar la cola el reproductor queda al final: se reinicia.
    if (_player.processingState == ProcessingState.completed) {
      await _player.seek(Duration.zero);
    }
    // `play()` no se espera: su futuro solo termina al pausar o acabar.
    unawaited(_player.play());
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> skipToNext() async {
    if (_queue.next() != null) await _loadCurrent();
  }

  @override
  Future<void> skipToPrevious() async {
    if (_queue.current == null) return;
    if (_player.position > _restartThreshold) {
      await _player.seek(Duration.zero);
      return;
    }
    final before = _queue.state.index;
    _queue.previous();
    if (_queue.state.index == before) {
      await _player.seek(Duration.zero);
    } else {
      await _loadCurrent();
    }
  }

  NormalizationMode get normalization => _normalization;

  /// Cambia la normalización de volumen y la aplica a la canción actual.
  Future<void> setNormalization(NormalizationMode mode) async {
    if (mode == _normalization) return;
    _normalization = mode;
    final song = _queue.current;
    if (song == null) return;
    final volume = await _normalizedVolume(song);
    if (_queue.current == song) await _player.setVolume(volume);
  }

  Future<void> setShuffle(bool enabled) async {
    _queue.setShuffle(enabled);
    _publishQueue();
  }

  Future<void> setRepeat(QueueRepeat mode) async {
    _queue.setRepeat(mode);
    _publishQueue();
  }

  // Los modos también pueden llegar desde el sistema (p. ej. Android Auto).
  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) =>
      setShuffle(shuffleMode != AudioServiceShuffleMode.none);

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) =>
      setRepeat(switch (repeatMode) {
        AudioServiceRepeatMode.none => QueueRepeat.off,
        AudioServiceRepeatMode.one => QueueRepeat.one,
        AudioServiceRepeatMode.all ||
        AudioServiceRepeatMode.group => QueueRepeat.all,
      });

  /// Si el usuario cierra la app desde recientes estando en pausa, se libera
  /// el servicio; si está sonando, la música continúa.
  @override
  Future<void> onTaskRemoved() async {
    if (!_player.playing) await stop();
  }

  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _player.dispose();
    await _queueState.close();
  }

  // ---------------------------------------------------------------------
  // Interno
  // ---------------------------------------------------------------------

  Future<void> _onCompleted() async {
    if (_queue.next(auto: true) == null) {
      // Fin de la cola: queda en pausa al inicio de la última canción.
      await _player.pause();
      await _player.seek(Duration.zero);
      return;
    }
    await _loadCurrent();
  }

  /// Carga en el reproductor la canción actual de la cola.
  Future<void> _loadCurrent({Duration? position, bool autoPlay = true}) async {
    _publishQueue();
    final song = _queue.current;
    if (song == null) {
      await _player.stop();
      return;
    }
    // Las etiquetas se leen a la vez que se prepara el archivo.
    final volume = _normalizedVolume(song)
        .timeout(_replayGainTimeout, onTimeout: () => 1);
    try {
      await _player.setAudioSource(
        AudioSource.uri(Uri.parse(song.uri)),
        initialPosition: position,
      );
      _failures = 0;
    } on PlayerInterruptedException {
      return; // otra carga más reciente tomó el relevo
    } catch (_) {
      // Archivo borrado o ilegible: se prueba con la siguiente, como mucho
      // una vuelta completa a la cola.
      if (_queue.current != song) return;
      _failures++;
      if (_failures < _queue.length && _queue.next() != null) {
        return _loadCurrent(autoPlay: autoPlay);
      }
      _failures = 0;
      await _player.stop();
      return;
    }
    // El volumen se ajusta antes de sonar para no empezar a todo volumen.
    final level = await volume;
    if (_queue.current != song) return;
    await _player.setVolume(level);
    if (autoPlay) unawaited(_player.play());
  }

  /// Volumen de [song] según la normalización elegida (1 si está apagada).
  Future<double> _normalizedVolume(Song song) async {
    if (_normalization == NormalizationMode.off) return 1;
    return normalizationVolume(await _replayGainOf(song), _normalization);
  }

  Future<ReplayGainInfo?> _replayGainOf(Song song) async {
    if (_replayGainCache.containsKey(song.id)) {
      return _replayGainCache[song.id];
    }
    ReplayGainInfo? info;
    try {
      info = await _readReplayGain(song.path);
    } on Object {
      info = null;
    }
    _replayGainCache[song.id] = info;
    while (_replayGainCache.length > _replayGainCacheSize) {
      _replayGainCache.remove(_replayGainCache.keys.first);
    }
    return info;
  }

  void _publishQueue() {
    final state = _queue.state;
    _queueState.add(state);
    queue.add([for (final song in state.songs) _toMediaItem(song)]);
    final current = state.current;
    mediaItem.add(current == null ? null : _toMediaItem(current));
    _broadcastState();
  }

  void _broadcastState() {
    final playing = _player.playing;
    final queueState = _queue.state;
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: switch (_player.processingState) {
          ProcessingState.idle => AudioProcessingState.idle,
          ProcessingState.loading => AudioProcessingState.loading,
          ProcessingState.buffering => AudioProcessingState.buffering,
          ProcessingState.ready => AudioProcessingState.ready,
          ProcessingState.completed => AudioProcessingState.completed,
        },
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: queueState.index < 0 ? null : queueState.index,
        shuffleMode: queueState.shuffle
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
        repeatMode: switch (queueState.repeat) {
          QueueRepeat.off => AudioServiceRepeatMode.none,
          QueueRepeat.all => AudioServiceRepeatMode.all,
          QueueRepeat.one => AudioServiceRepeatMode.one,
        },
      ),
    );
  }

  MediaItem _toMediaItem(Song song) {
    // En Android 10+ `audio_service` obtiene la carátula con
    // `ContentResolver.loadThumbnail` sobre el propio URI de la canción.
    final contentUri = 'content://media/external/audio/media/${song.id}';
    return MediaItem(
      id: song.uri,
      title: song.title,
      artist: song.artist,
      album: song.album,
      duration: song.duration,
      artUri: Uri.parse(contentUri),
      extras: {'songId': song.id, 'loadThumbnailUri': contentUri},
    );
  }
}
