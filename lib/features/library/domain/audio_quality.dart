import 'package:flutter/foundation.dart';

/// Nivel de calidad de un archivo, para colorear la insignia.
enum QualityTier {
  /// Sin pérdida con más de 16 bits o más de 48 kHz.
  hiRes,

  /// Sin pérdida (FLAC, WAV, ALAC...).
  lossless,

  /// Con pérdida a 256 kbps o más.
  high,

  /// Con pérdida entre 160 y 255 kbps.
  standard,

  /// Con pérdida por debajo de 160 kbps.
  low,

  /// No hay datos suficientes para juzgar.
  unknown,
}

/// Formato y calidad técnica de un archivo de audio, tal como los informa
/// MediaStore. Ningún dato es obligatorio: depende de la versión de Android
/// y de lo que el sistema haya podido leer del archivo.
@immutable
class AudioQuality {
  const AudioQuality({
    this.mimeType,
    this.extension,
    this.bitrate,
    this.sampleRate,
    this.bitsPerSample,
  });

  const AudioQuality.unknown()
    : mimeType = null,
      extension = null,
      bitrate = null,
      sampleRate = null,
      bitsPerSample = null;

  final String? mimeType;

  /// Extensión del archivo en minúsculas y sin punto (`mp3`, `flac`...).
  final String? extension;

  /// Bits por segundo.
  final int? bitrate;

  /// Hz.
  final int? sampleRate;
  final int? bitsPerSample;

  static const Set<String> _losslessFormats = {
    'FLAC',
    'WAV',
    'ALAC',
    'APE',
    'WV',
    'AIFF',
  };

  /// Nombre corto del formato (`MP3`, `FLAC`, `AAC`...), o `null`.
  String? get format {
    final byMime = switch (mimeType?.toLowerCase()) {
      'audio/mpeg' || 'audio/mp3' || 'audio/mpeg3' => 'MP3',
      'audio/flac' || 'audio/x-flac' => 'FLAC',
      'audio/aac' || 'audio/aacp' || 'audio/x-aac' => 'AAC',
      'audio/ogg' || 'application/ogg' || 'audio/vorbis' => 'OGG',
      'audio/opus' => 'OPUS',
      'audio/wav' || 'audio/x-wav' || 'audio/wave' => 'WAV',
      'audio/x-ms-wma' => 'WMA',
      'audio/x-ape' || 'audio/ape' => 'APE',
      'audio/aiff' || 'audio/x-aiff' => 'AIFF',
      'audio/x-wavpack' => 'WV',
      _ => null,
    };
    // MP4/M4A puede llevar AAC o ALAC: sin abrir el archivo no se distingue.
    if (byMime != null) return byMime;
    final ext = extension?.toLowerCase();
    if (ext == null || ext.isEmpty) return null;
    return switch (ext) {
      'm4a' || 'mp4' || 'm4b' => 'M4A',
      'oga' => 'OGG',
      'aif' => 'AIFF',
      _ => ext.toUpperCase(),
    };
  }

  bool get isLossless => _losslessFormats.contains(format);

  int? get bitrateKbps => bitrate == null ? null : (bitrate! / 1000).round();

  QualityTier get tier {
    if (isLossless) {
      final hiRes = (bitsPerSample ?? 0) > 16 || (sampleRate ?? 0) > 48000;
      return hiRes ? QualityTier.hiRes : QualityTier.lossless;
    }
    final kbps = bitrateKbps;
    if (kbps == null) return QualityTier.unknown;
    if (kbps >= 256) return QualityTier.high;
    if (kbps >= 160) return QualityTier.standard;
    return QualityTier.low;
  }

  /// Texto de la insignia: `FLAC · 24 bit/96 kHz`, `MP3 · 320 kbps`... o
  /// `null` si no se sabe ni el formato.
  String? get label {
    final name = format;
    if (name == null) return null;
    final details = <String>[];
    if (isLossless) {
      if (bitsPerSample != null && sampleRate != null) {
        details.add('$bitsPerSample bit/${formatSampleRate(sampleRate!)}');
      } else if (sampleRate != null) {
        details.add(formatSampleRate(sampleRate!));
      } else if (bitrateKbps != null) {
        details.add('$bitrateKbps kbps');
      }
    } else if (bitrateKbps != null) {
      details.add('$bitrateKbps kbps');
    }
    return [name, ...details].join(' · ');
  }

  /// Bitrate medio aproximado a partir del tamaño y la duración, para
  /// versiones de Android que no lo informan.
  static int? estimateBitrate(int? sizeBytes, Duration duration) {
    if (sizeBytes == null || sizeBytes <= 0) return null;
    final seconds = duration.inMilliseconds / 1000;
    if (seconds < 1) return null;
    return (sizeBytes * 8 / seconds).round();
  }
}

/// `44.1 kHz`, `48 kHz`, `96 kHz`.
String formatSampleRate(int hertz) {
  final khz = hertz / 1000;
  return khz == khz.roundToDouble()
      ? '${khz.round()} kHz'
      : '${khz.toStringAsFixed(1)} kHz';
}
