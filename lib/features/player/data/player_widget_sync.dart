import 'dart:async';

import 'package:flutter/services.dart';
import 'package:rxdart/rxdart.dart';

import '../../library/domain/song.dart';
import 'sympho_audio_handler.dart';

/// Conecta el reproductor con los widgets de la pantalla de inicio
/// (`PlayerWidgetBridge.kt`): les envía la canción y el estado actuales y
/// ejecuta las órdenes de sus botones.
///
/// Se arranca en `main()` y no depende de la interfaz, así que sigue
/// funcionando con la app en segundo plano.
class PlayerWidgetSync {
  PlayerWidgetSync(this._handler, {MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName =
      'com.carlosavellaneda.symphopk/player_widget';

  final SymphoAudioHandler _handler;
  final MethodChannel _channel;
  StreamSubscription<void>? _subscription;

  void start() {
    _channel.setMethodCallHandler(_onCall);
    _subscription =
        Rx.combineLatest2<Song?, bool, (Song?, bool)>(
              _handler.queueState.map((queue) => queue.current).distinct(),
              _handler.playbackState.map((state) => state.playing).distinct(),
              (song, playing) => (song, playing),
            )
            // Al cambiar de canción llegan varios eventos seguidos.
            .debounceTime(const Duration(milliseconds: 120))
            .listen((state) => _push(state.$1, state.$2));
  }

  Future<void> dispose() async {
    _channel.setMethodCallHandler(null);
    await _subscription?.cancel();
  }

  Future<Object?> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'toggle':
        if (_handler.playbackState.value.playing) {
          await _handler.pause();
        } else {
          await _handler.play();
        }
      case 'next':
        await _handler.skipToNext();
      case 'previous':
        await _handler.skipToPrevious();
      case 'requestState':
        await _push(
          _handler.queueState.value.current,
          _handler.playbackState.value.playing,
        );
      default:
        throw MissingPluginException('Orden desconocida: ${call.method}');
    }
    return null;
  }

  Future<void> _push(Song? song, bool playing) async {
    try {
      await _channel.invokeMethod<void>('update', {
        'songId': song?.id,
        'title': song?.title,
        'artist': song?.artist,
        'playing': playing,
      });
    } on MissingPluginException {
      // El lado nativo aún no está registrado (o no existe en esta
      // plataforma); pedirá el estado con `requestState` cuando lo esté.
    } on PlatformException {
      // Un fallo al pintar el widget no debe afectar a la reproducción.
    }
  }
}
