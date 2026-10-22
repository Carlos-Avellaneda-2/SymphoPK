import 'dart:async';
import 'dart:math' as math;

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
///
/// Usa dos reproductores para el fundido encadenado (crossfade): mientras
/// uno apaga la canción que termina, el otro arranca la siguiente. Fuera del
/// fundido solo suena el reproductor activo.
class SymphoAudioHandler extends BaseAudioHandler with SeekHandler {
  SymphoAudioHandler({
    AudioPlayer? player,
    AudioPlayer? crossfadePlayer,
    QueueManager? queueManager,
    ReplayGainReader? replayGainReader,
  }) : _players = [player ?? AudioPlayer(), crossfadePlayer ?? AudioPlayer()],
       _queue = queueManager ?? QueueManager(),
       _readReplayGain = replayGainReader ?? readReplayGain {
    _activePlayer = BehaviorSubject.seeded(_players.first);
    for (final player in _players) {
      _subscriptions
        ..add(player.playbackEventStream.listen((_) => _broadcastState()))
        ..add(player.playingStream.listen((_) => _broadcastState()))
        ..add(
          player.processingStateStream
              .where((state) => state == ProcessingState.completed)
              // La canción que se apaga en un fundido ya no es la actual.
              .where((_) => identical(player, _player))
              .listen((_) => _onCompleted()),
        );
    }
    _subscriptions.add(positionStream.listen(_maybeStartCrossfade));
  }

  /// Por encima de este punto, «anterior» reinicia la canción actual.
  static const Duration _restartThreshold = Duration(seconds: 3);

  /// Intervalo entre ajustes de volumen durante un fundido.
  static const Duration crossfadeStep = Duration(milliseconds: 50);

  /// Con menos tiempo restante no se empieza un fundido: la canción acaba
  /// antes de que la siguiente esté lista.
  static const Duration _minCrossfade = Duration(seconds: 1);

  final List<AudioPlayer> _players;
  late final BehaviorSubject<AudioPlayer> _activePlayer;

  /// Reproductor de la canción actual.
  AudioPlayer get _player => _activePlayer.value;

  AudioPlayer get _otherPlayer =>
      identical(_player, _players.first) ? _players.last : _players.first;

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

  /// Volumen (normalizado) de la canción actual.
  double _level = 1;

  int _crossfadeSeconds = 0;

  /// Reproductor que se está apagando; `null` fuera de un fundido.
  AudioPlayer? _fadingOut;
  Timer? _fadeTimer;
  bool _preparingCrossfade = false;

  /// Cambia con cada acción que invalida un fundido en preparación.
  int _crossfadeToken = 0;

  ValueStream<QueueState> get queueState => _queueState.stream;

  /// Cola en su orden original, sin barajar (para persistirla).
  List<Song> get originalQueue => _queue.originalOrder;

  /// Posición del reproductor activo; al empezar un fundido pasa a ser la
  /// de la canción nueva.
  Stream<Duration> get positionStream => Rx.merge([
    for (final player in _players)
      player.positionStream.where((_) => identical(player, _player)),
  ]);

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
  Future<void> pause() {
    _finishCrossfade();
    return _player.pause();
  }

  @override
  Future<void> seek(Duration position) {
    _finishCrossfade();
    return _player.seek(position);
  }

  @override
  Future<void> stop() async {
    _finishCrossfade();
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
    _finishCrossfade();
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
    if (_queue.current != song) return;
    _level = volume;
    // En pleno fundido el temporizador ya sube hacia el nuevo nivel.
    if (_fadingOut == null) await _player.setVolume(volume);
  }

  int get crossfadeSeconds => _crossfadeSeconds;

  /// Segundos de fundido entre canciones; `0` lo desactiva. Solo se funden
  /// las canciones que terminan solas, no los saltos manuales.
  void setCrossfade(int seconds) => _crossfadeSeconds = math.max(0, seconds);

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
    _fadeTimer?.cancel();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    for (final player in _players) {
      await player.dispose();
    }
    await _activePlayer.close();
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
    _finishCrossfade();
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
    _level = level;
    await _player.setVolume(level);
    if (autoPlay) unawaited(_player.play());
  }

  // ---------------------------------------------------------------------
  // Fundido encadenado
  // ---------------------------------------------------------------------

  /// Se llama con cada posición del reproductor activo: si la canción está
  /// por acabar, prepara la siguiente en el otro reproductor.
  void _maybeStartCrossfade(Duration position) {
    if (_crossfadeSeconds == 0 || _preparingCrossfade || _fadingOut != null) {
      return;
    }
    final player = _player;
    final duration = player.duration;
    if (!player.playing ||
        player.processingState != ProcessingState.ready ||
        duration == null) {
      return;
    }
    // «Repetir una» vuelve a empezar la misma canción, sin fundido.
    if (_queue.repeat == QueueRepeat.one) return;
    final fade = Duration(seconds: _crossfadeSeconds);
    // Las canciones muy cortas no se funden: casi no se oirían enteras.
    if (duration < fade * 2) return;
    final remaining = duration - position;
    if (remaining > fade || remaining < _minCrossfade) return;
    unawaited(_startCrossfade());
  }

  Future<void> _startCrossfade() async {
    final from = _queue.current;
    final song = _queue.peekNext();
    if (from == null || song == null) return;
    _preparingCrossfade = true;
    final token = _crossfadeToken;
    final outgoing = _player;
    final incoming = _otherPlayer;
    try {
      final volume = _normalizedVolume(song)
          .timeout(_replayGainTimeout, onTimeout: () => 1);
      try {
        await incoming.setVolume(0);
        await incoming.setAudioSource(AudioSource.uri(Uri.parse(song.uri)));
      } catch (_) {
        // Si no carga, la canción acaba sola y la cola sigue como siempre.
        await incoming.stop();
        return;
      }
      final level = await volume;
      // Mientras cargaba pudo cambiar todo: saltos, pausa, cola editada...
      final remaining =
          (outgoing.duration ?? Duration.zero) - outgoing.position;
      if (token != _crossfadeToken ||
          !identical(outgoing, _player) ||
          !outgoing.playing ||
          _queue.current != from ||
          _queue.peekNext() != song ||
          remaining < _minCrossfade) {
        await incoming.stop();
        return;
      }
      _queue.next(auto: true);
      _level = level;
      _fadingOut = outgoing;
      // Primero a sonar y luego el relevo: si el estado publicado pasara
      // por «en pausa», el servicio saldría de primer plano y Android no
      // deja volver a él desde segundo plano; el sistema congelaría la app
      // y la música se cortaría.
      unawaited(incoming.play());
      _activePlayer.add(incoming);
      _publishQueue();
      _runFade(outgoing, incoming, outgoing.volume, remaining);
    } finally {
      _preparingCrossfade = false;
    }
  }

  /// Baja [outgoing] y sube [incoming] con curvas de igual potencia, para
  /// que el volumen total no se hunda a mitad del fundido.
  void _runFade(
    AudioPlayer outgoing,
    AudioPlayer incoming,
    double outgoingLevel,
    Duration duration,
  ) {
    final steps = math.max(
      1,
      duration.inMilliseconds ~/ crossfadeStep.inMilliseconds,
    );
    var step = 0;
    _fadeTimer = Timer.periodic(crossfadeStep, (_) {
      step++;
      // Una pausa del sistema (llamada, auriculares) también lo termina.
      if (step >= steps || !incoming.playing) {
        _finishCrossfade();
        return;
      }
      final angle = step / steps * math.pi / 2;
      unawaited(outgoing.setVolume(outgoingLevel * math.cos(angle)));
      unawaited(incoming.setVolume(_level * math.sin(angle)));
    });
  }

  /// Termina en seco el fundido en curso (o cancela el que se prepara): la
  /// canción anterior se detiene y la actual queda a su volumen.
  void _finishCrossfade() {
    _crossfadeToken++;
    final outgoing = _fadingOut;
    if (outgoing == null) return;
    _fadeTimer?.cancel();
    _fadeTimer = null;
    _fadingOut = null;
    unawaited(outgoing.stop());
    unawaited(_player.setVolume(_level));
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
