import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:symphopk/features/player/domain/replay_gain.dart';

double dbToVolume(double db) => math.pow(10, db / 20).toDouble();

void main() {
  group('parseGainDb', () {
    test('acepta los formatos habituales', () {
      expect(parseGainDb('-6.54 dB'), -6.54);
      expect(parseGainDb('+1.20 dB'), 1.2);
      expect(parseGainDb('−3 dB'), -3);
      expect(parseGainDb('-6.54'), -6.54);
      expect(parseGainDb(' -2,5 DB '), -2.5);
    });

    test('rechaza valores vacíos, no numéricos o absurdos', () {
      expect(parseGainDb(null), isNull);
      expect(parseGainDb(''), isNull);
      expect(parseGainDb('alto'), isNull);
      expect(parseGainDb('-80 dB'), isNull);
    });
  });

  test('parsePeak', () {
    expect(parsePeak('0.988'), 0.988);
    expect(parsePeak('1,2'), 1.2);
    expect(parsePeak('0'), isNull);
    expect(parsePeak('x'), isNull);
    expect(parsePeak(null), isNull);
  });

  test('fromTags no distingue mayúsculas', () {
    final info = ReplayGainInfo.fromTags({
      'REPLAYGAIN_TRACK_GAIN': '-7.00 dB',
      'replaygain_track_peak': '0.95',
      'ReplayGain_Album_Gain': '-8.00 dB',
      'otra': 'cosa',
    });
    expect(
      info,
      const ReplayGainInfo(trackGain: -7, trackPeak: 0.95, albumGain: -8),
    );
    expect(info.isEmpty, isFalse);
    expect(ReplayGainInfo.fromTags(const {}).isEmpty, isTrue);
  });

  group('normalizationVolume', () {
    const info = ReplayGainInfo(trackGain: -10, albumGain: -12);

    test('desactivada o sin etiquetas no cambia el volumen', () {
      expect(normalizationVolume(info, NormalizationMode.off), 1);
      expect(normalizationVolume(null, NormalizationMode.track), 1);
      expect(
        normalizationVolume(const ReplayGainInfo(), NormalizationMode.track),
        1,
      );
    });

    test('baja las canciones fuertes respetando el margen', () {
      expect(
        normalizationVolume(info, NormalizationMode.track),
        closeTo(dbToVolume(-10 + normalizationHeadroomDb), 1e-9),
      );
      expect(
        normalizationVolume(info, NormalizationMode.album),
        closeTo(dbToVolume(-12 + normalizationHeadroomDb), 1e-9),
      );
    });

    test('nunca sube el volumen', () {
      expect(
        normalizationVolume(
          const ReplayGainInfo(trackGain: 3),
          NormalizationMode.track,
        ),
        1,
      );
    });

    test('usa la otra ganancia si falta la pedida', () {
      expect(
        normalizationVolume(
          const ReplayGainInfo(trackGain: -10),
          NormalizationMode.album,
        ),
        closeTo(dbToVolume(-4), 1e-9),
      );
      expect(
        normalizationVolume(
          const ReplayGainInfo(albumGain: -10),
          NormalizationMode.track,
        ),
        closeTo(dbToVolume(-4), 1e-9),
      );
    });

    test('el pico limita para no saturar', () {
      expect(
        normalizationVolume(
          const ReplayGainInfo(trackGain: -5, trackPeak: 2),
          NormalizationMode.track,
        ),
        0.5,
      );
    });
  });
}
