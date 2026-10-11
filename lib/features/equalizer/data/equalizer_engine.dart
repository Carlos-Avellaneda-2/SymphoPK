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

/// Implementación con `AndroidEqualizer` y `AndroidLoudnessEnhancer`. El
/// [pipeline] debe pasarse al `AudioPlayer` al crearlo.
class JustAudioEqualizerEngine implements EqualizerEngine {
  final AndroidEqualizer _equalizer = AndroidEqualizer();
  final AndroidLoudnessEnhancer _loudness = AndroidLoudnessEnhancer();

  late final AudioPipeline pipeline = AudioPipeline(
    androidAudioEffects: [_equalizer, _loudness],
  );

  @override
  Future<EqualizerCapabilities> capabilities() async {
    final parameters = await _equalizer.parameters;
    return EqualizerCapabilities(
      centerFrequencies: [
        for (final band in parameters.bands) band.centerFrequency,
      ],
      minDb: parameters.minDecibels,
      maxDb: parameters.maxDecibels,
    );
  }

  @override
  Future<void> setEnabled(bool enabled) => _equalizer.setEnabled(enabled);

  @override
  Future<void> setBandGain(int band, double gainDb) async {
    final parameters = await _equalizer.parameters;
    if (band < 0 || band >= parameters.bands.length) return;
    await parameters.bands[band].setGain(gainDb);
  }

  @override
  Future<void> setLoudness(double gainDb) async {
    await _loudness.setTargetGain(gainDb);
    await _loudness.setEnabled(gainDb > 0);
  }
}
