import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'equalizer_preset.dart';

/// Configuración del ecualizador elegida por el usuario. Es lo que se
/// persiste; no depende de las bandas del dispositivo.
@immutable
class EqualizerSettings {
  const EqualizerSettings({
    this.enabled = false,
    this.preset = EqualizerPreset.flat,
    this.customCurve = const [],
    this.loudnessDb = 0,
  });

  /// Refuerzo máximo de volumen. Por encima de unos 10 dB la mayoría de la
  /// música empieza a distorsionar.
  static const double maxLoudnessDb = 10;

  final bool enabled;
  final EqualizerPreset preset;

  /// Valores personalizados, guardados por frecuencia para poder adaptarlos
  /// si cambian las bandas (por ejemplo, al usar otra salida de audio).
  final List<GainPoint> customCurve;

  /// Refuerzo de volumen en dB, entre 0 y [maxLoudnessDb].
  final double loudnessDb;

  EqualizerSettings copyWith({
    bool? enabled,
    EqualizerPreset? preset,
    List<GainPoint>? customCurve,
    double? loudnessDb,
  }) => EqualizerSettings(
    enabled: enabled ?? this.enabled,
    preset: preset ?? this.preset,
    customCurve: customCurve ?? this.customCurve,
    loudnessDb: loudnessDb ?? this.loudnessDb,
  );

  /// Ganancias que corresponden a estas bandas con el preajuste actual.
  List<double> gainsFor(
    List<double> centerFrequencies, {
    required double minDb,
    required double maxDb,
  }) => gainsFromCurve(
    preset == EqualizerPreset.custom ? customCurve : presetCurve(preset),
    centerFrequencies,
    minDb: minDb,
    maxDb: maxDb,
  );

  String toJson() => jsonEncode({
    'enabled': enabled,
    'preset': preset.name,
    'custom': [
      for (final point in customCurve) [point.frequency, point.gain],
    ],
    'loudness': loudnessDb,
  });

  /// Devuelve los valores por defecto si [source] es nulo o no es válido.
  static EqualizerSettings fromJson(String? source) {
    if (source == null) return const EqualizerSettings();
    try {
      final data = jsonDecode(source) as Map<String, dynamic>;
      return EqualizerSettings(
        enabled: data['enabled'] as bool? ?? false,
        preset:
            EqualizerPreset.values.asNameMap()[data['preset']] ??
            EqualizerPreset.flat,
        customCurve: [
          for (final point in (data['custom'] as List? ?? const []))
            (
              frequency: ((point as List)[0] as num).toDouble(),
              gain: (point[1] as num).toDouble(),
            ),
        ],
        loudnessDb: ((data['loudness'] as num?)?.toDouble() ?? 0)
            .clamp(0, maxLoudnessDb)
            .toDouble(),
      );
    } on Object {
      return const EqualizerSettings();
    }
  }
}
