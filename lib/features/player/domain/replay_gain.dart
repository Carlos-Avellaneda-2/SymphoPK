import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Cómo se iguala el volumen entre canciones.
enum NormalizationMode {
  off('Desactivada'),

  /// Cada canción por separado.
  track('Por canción'),

  /// Respeta las diferencias de volumen dentro de un mismo álbum.
  album('Por álbum');

  const NormalizationMode(this.label);

  final String label;
}

/// Valores ReplayGain guardados en las etiquetas de un archivo.
@immutable
class ReplayGainInfo {
  const ReplayGainInfo({
    this.trackGain,
    this.trackPeak,
    this.albumGain,
    this.albumPeak,
  });

  /// dB que hay que sumar para llegar al nivel de referencia.
  final double? trackGain;

  /// Pico de la señal, donde 1.0 es el máximo sin saturar.
  final double? trackPeak;
  final double? albumGain;
  final double? albumPeak;

  bool get isEmpty => trackGain == null && albumGain == null;

  /// Lee las etiquetas estándar sin distinguir mayúsculas:
  /// `REPLAYGAIN_TRACK_GAIN`, `REPLAYGAIN_TRACK_PEAK`, etc.
  factory ReplayGainInfo.fromTags(Map<String, String> tags) {
    final lower = {
      for (final entry in tags.entries) entry.key.toLowerCase(): entry.value,
    };
    return ReplayGainInfo(
      trackGain: parseGainDb(lower['replaygain_track_gain']),
      trackPeak: parsePeak(lower['replaygain_track_peak']),
      albumGain: parseGainDb(lower['replaygain_album_gain']),
      albumPeak: parsePeak(lower['replaygain_album_peak']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReplayGainInfo &&
      other.trackGain == trackGain &&
      other.trackPeak == trackPeak &&
      other.albumGain == albumGain &&
      other.albumPeak == albumPeak;

  @override
  int get hashCode => Object.hash(trackGain, trackPeak, albumGain, albumPeak);
}

/// `-6.54 dB`, `+1.20 dB`, `−3 dB` (con signo menos tipográfico) o `-6.54`.
double? parseGainDb(String? value) {
  if (value == null) return null;
  final cleaned = value
      .trim()
      .replaceAll('−', '-')
      .replaceAll(RegExp(r'\s*dB$', caseSensitive: false), '')
      .replaceAll(',', '.');
  final gain = double.tryParse(cleaned);
  if (gain == null || gain.isNaN || gain.isInfinite) return null;
  // Valores fuera de este rango son etiquetas dañadas.
  return gain.abs() > 60 ? null : gain;
}

double? parsePeak(String? value) {
  if (value == null) return null;
  final peak = double.tryParse(value.trim().replaceAll(',', '.'));
  if (peak == null || peak.isNaN || peak <= 0) return null;
  return peak;
}

/// Margen sobre la referencia de ReplayGain (89 dB, unos −18 LUFS). La
/// mayoría de la música actual está muy por encima de esa referencia y sus
/// ganancias son negativas; sin margen, todo sonaría bastante más bajo.
/// Con 6 dB las canciones moderadas quedan casi igual y se bajan las más
/// fuertes.
const double normalizationHeadroomDb = 6;

/// Factor de volumen (0–1) que aplica la normalización a una canción.
///
/// Solo **baja** el volumen: subirlo exigiría amplificar por encima del
/// máximo, con riesgo de saturar y de forzar el altavoz. Sin etiquetas (o
/// con la normalización desactivada) devuelve 1. En modo álbum usa la
/// ganancia de pista si el archivo no trae la de álbum, y viceversa. Si se
/// conoce el pico, nunca devuelve un valor que lo haga saturar.
double normalizationVolume(ReplayGainInfo? info, NormalizationMode mode) {
  if (info == null || mode == NormalizationMode.off) return 1;
  final useAlbum = mode == NormalizationMode.album;
  final gain = useAlbum
      ? (info.albumGain ?? info.trackGain)
      : (info.trackGain ?? info.albumGain);
  if (gain == null) return 1;
  final peak = useAlbum
      ? (info.albumPeak ?? info.trackPeak)
      : (info.trackPeak ?? info.albumPeak);

  var volume = math.pow(10, (gain + normalizationHeadroomDb) / 20).toDouble();
  if (peak != null) volume = math.min(volume, 1 / peak);
  return volume.clamp(0.0, 1.0).toDouble();
}
