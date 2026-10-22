import 'dart:async';
import 'dart:math' as math;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:symphopk/features/player/data/replay_gain_reader.dart';
import 'package:symphopk/features/player/data/sympho_audio_handler.dart';
import 'package:symphopk/features/player/domain/queue_state.dart';
import 'package:symphopk/features/player/domain/replay_gain.dart';

import '../support/songs.dart';

/// Reproductor sin plataforma: guarda el estado que el handler le pide y
/// deja que el test emita posiciones y finales de canción.
class _FakePlayer extends Fake implements AudioPlayer {
  _FakePlayer(this.name);

  final String name;
  final _events = StreamController<PlaybackEvent>.broadcast();
  final _playingController = StreamController<bool>.broadcast();
  final _processing = StreamController<ProcessingState>.broadcast();
  final _positions = StreamController<Duration>.broadcast();

  @override
  bool playing = false;
  @override
  ProcessingState processingState = ProcessingState.idle;
  @override
  Duration? duration;
  @override
  Duration position = Duration.zero;
  @override
  double volume = 1;

  /// Duración de las canciones que se carguen.
  Duration songDuration = const Duration(minutes: 3);
  Uri? loaded;
  int loads = 0;

  @override
  Stream<PlaybackEvent> get playbackEventStream => _events.stream;
  @override
  Stream<bool> get playingStream => _playingController.stream;
  @override
  Stream<ProcessingState> get processingStateStream => _processing.stream;
  @override
  Stream<Duration> get positionStream => _positions.stream;
  @override
  Duration get bufferedPosition => Duration.zero;
  @override
  double get speed => 1;

  @override
  Future<Duration?> setAudioSource(
    AudioSource audioSource, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    loads++;
    loaded = (audioSource as UriAudioSource).uri;
    position = initialPosition ?? Duration.zero;
    duration = songDuration;
    _setProcessing(ProcessingState.ready);
    return duration;
  }

  @override
  Future<void> play() async {
    playing = true;
    _playingController.add(true);
  }

  @override
  Future<void> pause() async {
    playing = false;
    _playingController.add(false);
  }

  @override
  Future<void> stop() async {
    playing = false;
    loaded = null;
    _playingController.add(false);
    _setProcessing(ProcessingState.idle);
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    this.position = position ?? Duration.zero;
  }

  @override
  Future<void> setVolume(double volume) async => this.volume = volume;

  @override
  Future<void> dispose() async {}

  void emitPosition(Duration value) {
    position = value;
    _positions.add(value);
  }

  void complete() => _setProcessing(ProcessingState.completed);

  void _setProcessing(ProcessingState state) {
    processingState = state;
    _processing.add(state);
  }

  int? get songId =>
      loaded == null ? null : int.parse(loaded!.pathSegments.last);
}

void main() {
  late _FakePlayer a;
  late _FakePlayer b;
  late SymphoAudioHandler handler;
  ReplayGainInfo? gain;

  setUp(() {
    a = _FakePlayer('a');
    b = _FakePlayer('b');
    gain = null;
  });

  /// Ejecuta [body] con el tiempo simulado. El handler se crea dentro de la
  /// zona simulada para que sus suscripciones y temporizadores también lo
  /// estén.
  void run(
    void Function(FakeAsync async) body, {
    ReplayGainReader? replayGainReader,
  }) {
    fakeAsync((async) {
      handler = SymphoAudioHandler(
        player: a,
        crossfadePlayer: b,
        replayGainReader: replayGainReader ?? (_) async => gain,
      );
      body(async);
    });
  }

  int? currentId() => handler.queueState.value.current?.id;

  group('sin fundido', () {
    test('al terminar carga la siguiente en el mismo reproductor', () {
      run((async) {
        handler.playSongs(songs(3));
        async.flushMicrotasks();
        expect(a.songId, 1);
        a.emitPosition(const Duration(minutes: 2, seconds: 58));
        a.complete();
        async.flushMicrotasks();
        expect(a.songId, 2);
        expect(a.playing, isTrue);
        expect(b.loads, 0);
        expect(currentId(), 2);
      });
    });
  });

  group('fundido encadenado', () {
    const fade = 4;
    final nearEnd = const Duration(minutes: 3) - const Duration(seconds: 3);

    void startPlaying(FakeAsync async, {int count = 3, int index = 0}) {
      handler.setCrossfade(fade);
      handler.playSongs(songs(count), index: index);
      async.flushMicrotasks();
    }

    test('el estado publicado nunca pasa por «en pausa»', () {
      // Si lo hiciera, el servicio saldría de primer plano y Android no
      // deja volver a él con la app en segundo plano.
      run((async) {
        startPlaying(async);
        final playing = <bool>[];
        handler.playbackState.listen((state) => playing.add(state.playing));
        a.emitPosition(nearEnd);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 4));
        expect(currentId(), 2);
        expect(playing, isNotEmpty);
        expect(playing, everyElement(isTrue));
      });
    });

    test('prepara la siguiente y la funde con la actual', () {
      run((async) {
        startPlaying(async);
        a.emitPosition(nearEnd);
        async.flushMicrotasks();

        expect(b.songId, 2);
        expect(b.playing, isTrue);
        expect(a.playing, isTrue, reason: 'las dos suenan durante el fundido');
        expect(currentId(), 2);

        async.elapse(const Duration(milliseconds: 1500));
        expect(a.volume, inExclusiveRange(0, 1));
        expect(b.volume, inExclusiveRange(0, 1));
        // Igual potencia: la suma de las potencias se mantiene.
        expect(a.volume * a.volume + b.volume * b.volume, closeTo(1, 0.01));

        async.elapse(const Duration(seconds: 2));
        expect(a.playing, isFalse);
        expect(a.loaded, isNull);
        expect(b.volume, 1);
        expect(b.playing, isTrue);
      });
    });

    test('el final de la canción que se apaga no salta otra', () {
      run((async) {
        startPlaying(async);
        a.emitPosition(nearEnd);
        async.flushMicrotasks();
        a.complete();
        async.flushMicrotasks();
        expect(currentId(), 2);
        expect(b.songId, 2);
      });
    });

    test('la posición pasa a la del reproductor nuevo', () {
      run((async) {
        final positions = <Duration>[];
        handler.positionStream.listen(positions.add);
        startPlaying(async);
        a.emitPosition(nearEnd);
        async.flushMicrotasks();
        b.emitPosition(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(positions.last, const Duration(seconds: 1));
        expect(handler.position, const Duration(seconds: 1));
      });
    });

    test('la siguiente transición vuelve al primer reproductor', () {
      run((async) {
        startPlaying(async);
        a.emitPosition(nearEnd);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 4));
        b.emitPosition(nearEnd);
        async.flushMicrotasks();
        expect(a.songId, 3);
        expect(currentId(), 3);
      });
    });

    test('pausar en pleno fundido lo termina', () {
      run((async) {
        startPlaying(async);
        a.emitPosition(nearEnd);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 1));
        handler.pause();
        async.flushMicrotasks();
        expect(a.playing, isFalse);
        expect(a.loaded, isNull);
        expect(b.playing, isFalse);
        expect(b.volume, 1);
        async.elapse(const Duration(seconds: 5));
        expect(b.volume, 1, reason: 'el temporizador ya no corre');
      });
    });

    test('saltar en pleno fundido carga en el reproductor nuevo', () {
      run((async) {
        startPlaying(async);
        a.emitPosition(nearEnd);
        async.flushMicrotasks();
        handler.skipToNext();
        async.flushMicrotasks();
        expect(a.loaded, isNull);
        expect(b.songId, 3);
        expect(b.volume, 1);
        expect(currentId(), 3);
      });
    });

    test('no funde lejos del final', () {
      run((async) {
        startPlaying(async);
        a.emitPosition(const Duration(minutes: 2));
        async.flushMicrotasks();
        expect(b.loads, 0);
      });
    });

    test('no funde con «repetir una»', () {
      run((async) {
        startPlaying(async);
        handler.setRepeat(QueueRepeat.one);
        a.emitPosition(nearEnd);
        async.flushMicrotasks();
        expect(b.loads, 0);
      });
    });

    test('no funde en la última canción de la cola', () {
      run((async) {
        startPlaying(async, index: 2);
        a.emitPosition(nearEnd);
        async.flushMicrotasks();
        expect(b.loads, 0);
      });
    });

    test('con «repetir todas» funde de la última a la primera', () {
      run((async) {
        startPlaying(async, index: 2);
        handler.setRepeat(QueueRepeat.all);
        a.emitPosition(nearEnd);
        async.flushMicrotasks();
        expect(b.songId, 1);
      });
    });

    test('no funde canciones demasiado cortas', () {
      run((async) {
        a.songDuration = const Duration(seconds: 7);
        startPlaying(async);
        a.emitPosition(const Duration(seconds: 4));
        async.flushMicrotasks();
        expect(b.loads, 0);
      });
    });

    test('desactivado no funde', () {
      run((async) {
        startPlaying(async);
        handler.setCrossfade(0);
        a.emitPosition(nearEnd);
        async.flushMicrotasks();
        expect(b.loads, 0);
      });
    });
  });

  group('normalización', () {
    final expected = math.pow(10, (-10 + normalizationHeadroomDb) / 20);

    test('ajusta el volumen antes de sonar', () {
      run((async) {
        gain = const ReplayGainInfo(trackGain: -10);
        handler.setNormalization(NormalizationMode.track);
        handler.playSongs(songs(2));
        async.flushMicrotasks();
        expect(a.volume, closeTo(expected, 1e-9));
        expect(a.playing, isTrue);
      });
    });

    test('cambiarla se aplica a la canción actual', () {
      run((async) {
        gain = const ReplayGainInfo(trackGain: -10);
        handler.playSongs(songs(2));
        async.flushMicrotasks();
        expect(a.volume, 1);
        handler.setNormalization(NormalizationMode.track);
        async.flushMicrotasks();
        expect(a.volume, closeTo(expected, 1e-9));
        handler.setNormalization(NormalizationMode.off);
        async.flushMicrotasks();
        expect(a.volume, 1);
      });
    });

    test('el fundido sube la siguiente hasta su nivel normalizado', () {
      run((async) {
        gain = const ReplayGainInfo(trackGain: -10);
        handler.setNormalization(NormalizationMode.track);
        handler.setCrossfade(4);
        handler.playSongs(songs(2));
        async.flushMicrotasks();
        a.emitPosition(const Duration(minutes: 2, seconds: 57));
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 4));
        expect(b.volume, closeTo(expected, 1e-9));
      });
    });

    test('si leer las etiquetas falla suena sin normalizar', () {
      run((async) {
        handler.setNormalization(NormalizationMode.track);
        handler.playSongs(songs(1));
        async.flushMicrotasks();
        expect(a.volume, 1);
        expect(a.playing, isTrue);
      }, replayGainReader: (_) async => throw const FormatException());
    });
  });
}
