import 'dart:math' as math;

/// Preajustes del ecualizador. [custom] no tiene curva propia: representa
/// los valores que el usuario ha movido a mano.
enum EqualizerPreset {
  flat('Plano'),
  pop('Pop'),
  rock('Rock'),
  jazz('Jazz'),
  classical('Clásica'),
  bassBoost('Bass Boost'),
  vocal('Vocal'),
  custom('Personalizado');

  const EqualizerPreset(this.label);

  final String label;
}

/// Punto de una curva de ecualización: ganancia en dB a una frecuencia.
typedef GainPoint = ({double frequency, double gain});

// Las curvas se definen por frecuencia y no por banda porque cada
// dispositivo tiene un número de bandas y unas frecuencias distintas.
const List<double> _referenceFrequencies = [60, 230, 910, 3600, 14000];

const Map<EqualizerPreset, List<double>> _referenceGains = {
  EqualizerPreset.flat: [0, 0, 0, 0, 0],
  EqualizerPreset.pop: [-1, 2, 4, 2, -1],
  EqualizerPreset.rock: [5, 3, -1, 3, 5],
  EqualizerPreset.jazz: [3, 1, -1, 2, 3],
  EqualizerPreset.classical: [4, 2, -2, 3, 4],
  EqualizerPreset.bassBoost: [7, 4, 0, 0, 0],
  EqualizerPreset.vocal: [-3, 0, 4, 3, -1],
};

/// Curva de referencia de un preajuste; vacía para [EqualizerPreset.custom].
List<GainPoint> presetCurve(EqualizerPreset preset) {
  final gains = _referenceGains[preset];
  if (gains == null) return const [];
  return [
    for (var i = 0; i < gains.length; i++)
      (frequency: _referenceFrequencies[i], gain: gains[i]),
  ];
}

/// Ganancia de cada banda del dispositivo para un preajuste.
///
/// [centerFrequencies] son las frecuencias centrales (Hz) que informa el
/// dispositivo y [minDb]/[maxDb] su rango admitido.
List<double> presetGains(
  EqualizerPreset preset,
  List<double> centerFrequencies, {
  required double minDb,
  required double maxDb,
}) => gainsFromCurve(
  presetCurve(preset),
  centerFrequencies,
  minDb: minDb,
  maxDb: maxDb,
);

/// Adapta una curva cualquiera a las bandas del dispositivo: interpola en
/// escala logarítmica de frecuencia (como percibe el oído) y recorta al
/// rango admitido. Fuera de los extremos de la curva se mantiene el valor
/// del extremo.
List<double> gainsFromCurve(
  List<GainPoint> curve,
  List<double> centerFrequencies, {
  required double minDb,
  required double maxDb,
}) {
  final points = [...curve]..sort((a, b) => a.frequency.compareTo(b.frequency));
  return [
    for (final frequency in centerFrequencies)
      _interpolate(points, frequency).clamp(minDb, maxDb).toDouble(),
  ];
}

double _interpolate(List<GainPoint> points, double frequency) {
  if (points.isEmpty) return 0;
  if (frequency <= points.first.frequency) return points.first.gain;
  if (frequency >= points.last.frequency) return points.last.gain;
  for (var i = 1; i < points.length; i++) {
    final low = points[i - 1];
    final high = points[i];
    if (frequency > high.frequency) continue;
    final span = math.log(high.frequency) - math.log(low.frequency);
    if (span == 0) return high.gain;
    final t = (math.log(frequency) - math.log(low.frequency)) / span;
    return low.gain + (high.gain - low.gain) * t;
  }
  return points.last.gain;
}

/// `60 Hz`, `910 Hz`, `3.6 kHz`, `14 kHz`.
String formatFrequency(double hertz) {
  if (hertz < 1000) return '${hertz.round()} Hz';
  final kilo = hertz / 1000;
  final text = kilo >= 10 || kilo == kilo.roundToDouble()
      ? kilo.round().toString()
      : kilo.toStringAsFixed(1);
  return '$text kHz';
}

/// `+3 dB`, `-1.5 dB`, `0 dB`.
String formatGain(double decibels) {
  final rounded = (decibels * 10).round() / 10;
  if (rounded == 0) return '0 dB';
  final text = rounded == rounded.roundToDouble()
      ? rounded.round().abs().toString()
      : rounded.abs().toStringAsFixed(1);
  return '${rounded > 0 ? '+' : '-'}$text dB';
}
