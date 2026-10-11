import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:rxdart/rxdart.dart';

import '../../../core/database/key_value_store.dart';
import '../domain/equalizer_preset.dart';
import '../domain/equalizer_settings.dart';
import 'equalizer_engine.dart';

/// Estado del ecualizador tal como lo necesita la interfaz.
@immutable
class EqualizerState {
  const EqualizerState({
    required this.settings,
    this.capabilities,
    this.gains = const [],
  });

  final EqualizerSettings settings;

  /// `null` mientras el dispositivo no ha informado de sus bandas.
  final EqualizerCapabilities? capabilities;

  /// Ganancia actual de cada banda, en el mismo orden que las bandas.
  final List<double> gains;

  bool get isAvailable => capabilities != null;
}

/// Aplica la configuración del usuario a los efectos de audio, en tiempo
/// real, y la guarda para restaurarla en el siguiente arranque.
class EqualizerController {
  EqualizerController(this._engine, this._store);

  static const String storageKey = 'equalizer.settings';

  final EqualizerEngine _engine;
  final KeyValueStore _store;
  final _state = BehaviorSubject<EqualizerState>.seeded(
    const EqualizerState(settings: EqualizerSettings()),
  );

  ValueStream<EqualizerState> get state => _state.stream;

  EqualizerSettings get _settings => _state.value.settings;

  /// Carga la configuración guardada y la aplica en cuanto el dispositivo
  /// informe de sus bandas. No bloquea el arranque de la app.
  Future<void> init() async {
    final saved = EqualizerSettings.fromJson(await _store.read(storageKey));
    _state.add(EqualizerState(settings: saved));
    unawaited(_awaitCapabilities());
  }

  Future<void> _awaitCapabilities() async {
    try {
      final capabilities = await _engine.capabilities();
      _emit(_settings, capabilities: capabilities);
      await _applyAll();
    } on Object {
      // Dispositivo sin ecualizador: la pantalla lo indicará.
    }
  }

  Future<void> setEnabled(bool enabled) async {
    _emit(_settings.copyWith(enabled: enabled));
    await _applyAll();
    await _save();
  }

  Future<void> selectPreset(EqualizerPreset preset) async {
    final capabilities = _state.value.capabilities;
    var settings = _settings.copyWith(preset: preset);
    // Al elegir «Personalizado» sin valores previos se parte de lo que
    // suena ahora, para que el cambio no altere el sonido.
    if (preset == EqualizerPreset.custom &&
        settings.customCurve.isEmpty &&
        capabilities != null) {
      settings = settings.copyWith(
        customCurve: _curve(capabilities, _state.value.gains),
      );
    }
    _emit(settings);
    await _applyAll();
    await _save();
  }

  /// Mueve una banda. Cualquier ajuste manual pasa a «Personalizado»,
  /// partiendo de los valores que se estaban oyendo.
  Future<void> setBandGain(int band, double gainDb) async {
    final capabilities = _state.value.capabilities;
    if (capabilities == null || band < 0 || band >= capabilities.bandCount) {
      return;
    }
    final gains = [..._state.value.gains];
    gains[band] = gainDb
        .clamp(capabilities.minDb, capabilities.maxDb)
        .toDouble();
    _emit(
      _settings.copyWith(
        preset: EqualizerPreset.custom,
        customCurve: _curve(capabilities, gains),
      ),
    );
    if (_settings.enabled) await _engine.setBandGain(band, gains[band]);
  }

  /// Guarda tras soltar un deslizador, para no escribir en cada movimiento.
  Future<void> commit() => _save();

  Future<void> setLoudness(double gainDb) async {
    final value = gainDb.clamp(0, EqualizerSettings.maxLoudnessDb).toDouble();
    _emit(_settings.copyWith(loudnessDb: value));
    if (_settings.enabled) await _engine.setLoudness(value);
  }

  /// Vuelve a plano y sin refuerzo, conservando si está activado.
  Future<void> reset() async {
    _emit(EqualizerSettings(enabled: _settings.enabled));
    await _applyAll();
    await _save();
  }

  Future<void> dispose() => _state.close();

  void _emit(
    EqualizerSettings settings, {
    EqualizerCapabilities? capabilities,
  }) {
    final caps = capabilities ?? _state.value.capabilities;
    _state.add(
      EqualizerState(
        settings: settings,
        capabilities: caps,
        gains: caps == null
            ? const []
            : settings.gainsFor(
                caps.centerFrequencies,
                minDb: caps.minDb,
                maxDb: caps.maxDb,
              ),
      ),
    );
  }

  Future<void> _applyAll() async {
    final current = _state.value;
    if (!current.isAvailable) return;
    try {
      if (current.settings.enabled) {
        for (var band = 0; band < current.gains.length; band++) {
          await _engine.setBandGain(band, current.gains[band]);
        }
      }
      await _engine.setEnabled(current.settings.enabled);
      await _engine.setLoudness(
        current.settings.enabled ? current.settings.loudnessDb : 0,
      );
    } on Object {
      // Un fallo del efecto de audio no debe interrumpir la reproducción.
    }
  }

  Future<void> _save() => _store.write(storageKey, _settings.toJson());

  List<GainPoint> _curve(
    EqualizerCapabilities capabilities,
    List<double> gains,
  ) => [
    for (var i = 0; i < capabilities.bandCount; i++)
      (frequency: capabilities.centerFrequencies[i], gain: gains[i]),
  ];
}
