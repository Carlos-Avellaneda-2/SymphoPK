import 'package:just_audio/just_audio.dart';

/// Bandas y rango que admite el ecualizador del dispositivo.
class EqualizerCapabilities {
  const EqualizerCapabilities({
    required this.centerFrequencies,
    required this.minDb,
    required this.maxDb,
  });

  /// Frecuencia central de cada banda, en Hz.
  final List<double> centerFrequencies;
  final double minDb;
  final double maxDb;

  int get bandCount => centerFrequencies.length;
}

/// Efectos de audio del sistema. La interfaz aísla `just_audio` para poder
/// probar la lógica del ecualizador sin dispositivo.
abstract interface class EqualizerEngine {
  /// Se completa cuando el reproductor está activo y el dispositivo informa
  /// de sus bandas; puede tardar hasta que se carga la primera canción.
  Future<EqualizerCapabilities> capabilities();

  Future<void> setEnabled(bool enabled);

  Future<void> setBandGain(int band, double gainDb);

  /// Refuerzo de volumen; `0` lo desactiva.
  Future<void> setLoudness(double gainDb);
}

/// Implementación con `AndroidEqualizer` y `AndroidLoudnessEnhancer`. Cada
/// reproductor necesita su propia cadena de efectos (un efecto no puede
/// estar en dos a la vez), así que hay una por cada uno de los [pipelines],
/// que deben pasarse a los `AudioPlayer` al crearlos. Los ajustes se aplican
/// a todas por igual.
class JustAudioEqualizerEngine implements EqualizerEngine {
  JustAudioEqualizerEngine({int players = 2})
    : _chains = List.generate(players, (_) => _EffectChain()) {
    for (final chain in _chains) {
      // Las bandas solo existen cuando el reproductor de la cadena se activa
      // por primera vez; entonces recibe las ganancias pedidas hasta ahora.
      chain.equalizer.parameters.then((parameters) {
        chain.parameters = parameters;
        for (final entry in _gains.entries) {
          _applyGain(parameters, entry.key, entry.value);
        }
      });
    }
  }

  final List<_EffectChain> _chains;

  /// Última ganancia pedida para cada banda.
  final _gains = <int, double>{};

  List<AudioPipeline> get pipelines => [
    for (final chain in _chains) chain.pipeline,
  ];

  @override
  Future<EqualizerCapabilities> capabilities() async {
    // Sirve la del primer reproductor que se active: todas son iguales.
    final parameters = await Future.any([
      for (final chain in _chains) chain.equalizer.parameters,
    ]);
    return EqualizerCapabilities(
      centerFrequencies: [
        for (final band in parameters.bands) band.centerFrequency,
      ],
      minDb: parameters.minDecibels,
      maxDb: parameters.maxDecibels,
    );
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    for (final chain in _chains) {
      await chain.equalizer.setEnabled(enabled);
    }
  }

  @override
  Future<void> setBandGain(int band, double gainDb) async {
    _gains[band] = gainDb;
    for (final chain in _chains) {
      final parameters = chain.parameters;
      if (parameters != null) await _applyGain(parameters, band, gainDb);
    }
  }

  Future<void> _applyGain(
    AndroidEqualizerParameters parameters,
    int band,
    double gainDb,
  ) async {
    if (band < 0 || band >= parameters.bands.length) return;
    await parameters.bands[band].setGain(gainDb);
  }

  @override
  Future<void> setLoudness(double gainDb) async {
    for (final chain in _chains) {
      await chain.loudness.setTargetGain(gainDb);
      await chain.loudness.setEnabled(gainDb > 0);
    }
  }
}

class _EffectChain {
  final AndroidEqualizer equalizer = AndroidEqualizer();
  final AndroidLoudnessEnhancer loudness = AndroidLoudnessEnhancer();

  late final AudioPipeline pipeline = AudioPipeline(
    androidAudioEffects: [equalizer, loudness],
  );

  /// Bandas del ecualizador, cuando ya se conocen.
  AndroidEqualizerParameters? parameters;
}
