import 'dart:async';

import 'package:rxdart/rxdart.dart';

import '../../library/domain/song.dart';
import '../domain/playback_session.dart';
import 'playback_session_store.dart';
import 'sympho_audio_handler.dart';

/// Mantiene la sesión guardada al día y la restaura al arrancar.
class PlaybackSessionSync {
  PlaybackSessionSync(this._handler, this._store);

  final SymphoAudioHandler _handler;
  final PlaybackSessionStore _store;
  final _subscriptions = <StreamSubscription<void>>[];

  /// Recupera la última cola y posición, sin empezar a reproducir, y a
  /// partir de ahí guarda los cambios. Debe llamarse con la biblioteca ya
  /// escaneada.
  Future<void> restoreAndStart(Map<int, Song> songsById) async {
    // Si el servicio ya tiene cola (la app se reabre con música sonando) no
    // hay nada que restaurar.
    if (_handler.queueState.value.isEmpty) {
      final saved = await _store.load();
      final resolved = saved == null ? null : resolveSession(saved, songsById);
      if (saved != null && resolved != null) {
        await _handler.restoreSession(
          original: resolved.original,
          order: resolved.order,
          index: resolved.index,
          shuffle: saved.shuffle,
          repeat: saved.repeat,
          position: resolved.position,
        );
      }
    }
    _start();
  }

  void _start() {
    _subscriptions
      // skip(1): el valor actual ya está guardado (o es la cola vacía
      // inicial, que no debe pisar una sesión no restaurable).
      ..add(
        _handler.queueState
            .skip(1)
            .debounceTime(const Duration(milliseconds: 400))
            .listen((_) => _saveQueue()),
      )
      ..add(
        _handler.positionStream
            .throttleTime(const Duration(seconds: 5), trailing: true)
            .listen(_store.savePosition),
      )
      ..add(
        _handler.playbackState
            .map((state) => state.playing)
            .distinct()
            .where((playing) => !playing)
            .listen((_) => _store.savePosition(_handler.position)),
      );
  }

  Future<void> _saveQueue() {
    final state = _handler.queueState.value;
    if (state.isEmpty) return _store.clear();
    return _store.save(
      PlaybackSession(
        originalIds: [for (final song in _handler.originalQueue) song.id],
        orderIds: [for (final song in state.songs) song.id],
        index: state.index,
        shuffle: state.shuffle,
        repeat: state.repeat,
        position: _handler.position,
      ),
    );
  }

  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
  }
}
