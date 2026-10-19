import 'package:flutter_test/flutter_test.dart';
import 'package:symphopk/features/library/data/media_store_scanner.dart';
import 'package:symphopk/features/library/domain/audio_quality.dart';

void main() {
  group('formato', () {
    test('se deduce del tipo MIME', () {
      const cases = {
        'audio/mpeg': 'MP3',
        'audio/flac': 'FLAC',
        'audio/x-flac': 'FLAC',
        'audio/aac': 'AAC',
        'audio/ogg': 'OGG',
        'application/ogg': 'OGG',
        'audio/opus': 'OPUS',
        'audio/x-wav': 'WAV',
        'audio/x-ms-wma': 'WMA',
      };
      cases.forEach((mime, format) {
        expect(AudioQuality(mimeType: mime).format, format, reason: mime);
      });
    });

    test('ignora mayúsculas en el MIME', () {
      expect(const AudioQuality(mimeType: 'Audio/MPEG').format, 'MP3');
    });

    test('sin MIME conocido usa la extensión', () {
      expect(
        const AudioQuality(mimeType: 'audio/mp4', extension: 'm4a').format,
        'M4A',
        reason: 'MP4 puede ser AAC o ALAC',
      );
      expect(const AudioQuality(extension: 'aif').format, 'AIFF');
      expect(const AudioQuality(extension: 'dsf').format, 'DSF');
    });

    test('sin MIME ni extensión no hay formato', () {
      expect(const AudioQuality.unknown().format, isNull);
      expect(const AudioQuality(extension: '').format, isNull);
    });
  });

  group('nivel', () {
    test('sin pérdida y alta resolución', () {
      expect(
        const AudioQuality(
          mimeType: 'audio/flac',
          bitsPerSample: 16,
          sampleRate: 44100,
        ).tier,
        QualityTier.lossless,
      );
      expect(
        const AudioQuality(mimeType: 'audio/flac', bitsPerSample: 24).tier,
        QualityTier.hiRes,
      );
      expect(
        const AudioQuality(mimeType: 'audio/wav', sampleRate: 96000).tier,
        QualityTier.hiRes,
      );
      expect(
        const AudioQuality(mimeType: 'audio/flac').tier,
        QualityTier.lossless,
        reason: 'sin datos de resolución no se presume alta resolución',
      );
    });

    test('con pérdida según el bitrate', () {
      QualityTier tier(int bps) =>
          AudioQuality(mimeType: 'audio/mpeg', bitrate: bps).tier;
      expect(tier(320000), QualityTier.high);
      expect(tier(256000), QualityTier.high);
      expect(tier(192000), QualityTier.standard);
      expect(tier(160000), QualityTier.standard);
      expect(tier(128000), QualityTier.low);
      expect(
        const AudioQuality(mimeType: 'audio/mpeg').tier,
        QualityTier.unknown,
      );
    });
  });

  group('texto de la insignia', () {
    test('con pérdida muestra los kbps', () {
      expect(
        const AudioQuality(mimeType: 'audio/mpeg', bitrate: 320000).label,
        'MP3 · 320 kbps',
      );
      expect(
        const AudioQuality(mimeType: 'audio/aac', bitrate: 255600).label,
        'AAC · 256 kbps',
      );
    });

    test('sin pérdida muestra bits y frecuencia', () {
      expect(
        const AudioQuality(
          mimeType: 'audio/flac',
          bitsPerSample: 24,
          sampleRate: 96000,
          bitrate: 2400000,
        ).label,
        'FLAC · 24 bit/96 kHz',
      );
      expect(
        const AudioQuality(
          mimeType: 'audio/flac',
          bitsPerSample: 16,
          sampleRate: 44100,
        ).label,
        'FLAC · 16 bit/44.1 kHz',
      );
    });

    test('sin pérdida con datos parciales usa lo que haya', () {
      expect(
        const AudioQuality(mimeType: 'audio/flac', sampleRate: 48000).label,
        'FLAC · 48 kHz',
      );
      expect(
        const AudioQuality(mimeType: 'audio/flac', bitrate: 950000).label,
        'FLAC · 950 kbps',
      );
      expect(const AudioQuality(mimeType: 'audio/flac').label, 'FLAC');
    });

    test('sin formato no hay insignia', () {
      expect(const AudioQuality(bitrate: 320000).label, isNull);
    });
  });

  test('formatSampleRate', () {
    expect(formatSampleRate(44100), '44.1 kHz');
    expect(formatSampleRate(48000), '48 kHz');
    expect(formatSampleRate(192000), '192 kHz');
  });

  group('estimateBitrate', () {
    test('calcula bits por segundo con el tamaño y la duración', () {
      // 3 minutos a 320 kbps son 7,2 MB.
      expect(
        AudioQuality.estimateBitrate(7200000, const Duration(minutes: 3)),
        320000,
      );
    });

    test('devuelve null sin datos válidos', () {
      expect(
        AudioQuality.estimateBitrate(null, const Duration(minutes: 3)),
        isNull,
      );
      expect(
        AudioQuality.estimateBitrate(0, const Duration(minutes: 3)),
        isNull,
      );
      expect(AudioQuality.estimateBitrate(1000, Duration.zero), isNull);
    });
  });

  group('MediaStoreScanner.songFromRow', () {
    Map<String, Object?> row(Map<String, Object?> extra) => {
      'id': 1,
      'uri': 'content://media/external/audio/media/1',
      'title': 'Canción',
      'displayName': 'cancion.flac',
      'durationMs': 180000,
      ...extra,
    };

    test('lee el formato y la calidad del archivo', () {
      final song = MediaStoreScanner.songFromRow(
        row({
          'mimeType': 'audio/flac',
          'bitrate': 1000000,
          'sampleRate': 44100,
          'bitsPerSample': 16,
        }),
      )!;
      expect(song.quality.format, 'FLAC');
      expect(song.quality.extension, 'flac');
      expect(song.quality.label, 'FLAC · 16 bit/44.1 kHz');
    });

    test('estima el bitrate si el sistema no lo informa', () {
      final song = MediaStoreScanner.songFromRow(
        row({
          'displayName': 'tema.mp3',
          'mimeType': 'audio/mpeg',
          'sizeBytes': 7200000,
        }),
      )!;
      expect(song.quality.label, 'MP3 · 320 kbps');
    });

    test('sin datos de calidad la canción sigue siendo válida', () {
      final song = MediaStoreScanner.songFromRow(row({}))!;
      expect(song.quality.format, 'FLAC', reason: 'por la extensión');
      expect(song.quality.bitrate, isNull);
    });
  });
}
