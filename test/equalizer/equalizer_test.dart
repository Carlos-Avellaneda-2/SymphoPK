import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:symphopk/features/equalizer/data/equalizer_controller.dart';
import 'package:symphopk/features/equalizer/data/equalizer_engine.dart';
import 'package:symphopk/features/equalizer/domain/equalizer_preset.dart';
import 'package:symphopk/features/equalizer/domain/equalizer_settings.dart';

import '../support/memory_key_value_store.dart';

class _FakeEngine implements EqualizerEngine {
  _FakeEngine({this.ready = true});

  /// Si es `false`, las bandas no llegan hasta llamar a [becomeReady].
  bool ready;
  final _readyCompleter = Completer<void>();

  static const caps = EqualizerCapabilities(
    centerFrequencies: [60, 230, 910, 3600, 14000],
    minDb: -15,
    maxDb: 15,
  );

  bool? enabled;
  double? loudness;
  final Map<int, double> bandGains = {};

  void becomeReady() => _readyCompleter.complete();

  @override
  Future<EqualizerCapabilities> capabilities() async {
    if (!ready) await _readyCompleter.future;
    return caps;
  }

  @override
  Future<void> setBandGain(int band, double gainDb) async =>
      bandGains[band] = gainDb;

  @override
  Future<void> setEnabled(bool value) async => enabled = value;

  @override
  Future<void> setLoudness(double gainDb) async => loudness = gainDb;
}

void main() {
  const fiveBands = <double>[60, 230, 910, 3600, 14000];

  group('presetGains', () {
    test('plano deja todas las bandas a cero', () {
      expect(
        presetGains(EqualizerPreset.flat, fiveBands, minDb: -15, maxDb: 15),
        everyElement(0),
      );
    });

    test('en las frecuencias de referencia devuelve la curva exacta', () {
      expect(
        presetGains(EqualizerPreset.rock, fiveBands, minDb: -15, maxDb: 15),
        [5, 3, -1, 3, 5],
      );
      expect(
        presetGains(
          EqualizerPreset.bassBoost,
          fiveBands,
          minDb: -15,
          maxDb: 15,
        ),
        [7, 4, 0, 0, 0],
      );
    });

    test('se adapta a un número distinto de bandas', () {
      final ten = <double>[
        31,
        62,
        125,
        250,
        500,
        1000,
        2000,
        4000,
        8000,
        16000,
      ];
      final gains = presetGains(
        EqualizerPreset.bassBoost,
        ten,
        minDb: -12,
        maxDb: 12,
      );
      expect(gains.length, 10);
      expect(gains.first, 7, reason: 'por debajo de la curva usa el extremo');
      expect(gains[1], closeTo(7, 0.2));
      expect(gains[2], inExclusiveRange(4, 7), reason: 'interpola 60–230 Hz');
      expect(gains.sublist(5), everyElement(0));

      final three = presetGains(
        EqualizerPreset.vocal,
        const [100, 1000, 10000],
        minDb: -12,
        maxDb: 12,
      );
      expect(three.length, 3);
      expect(three[1], greaterThan(three[0]), reason: 'realza los medios');
    });

    test('interpola en escala logarítmica', () {
      // 117.5 Hz es el punto medio geométrico entre 60 y 230 Hz.
      final gain = presetGains(
        EqualizerPreset.bassBoost,
        const [117.47],
        minDb: -15,
        maxDb: 15,
      ).single;
      expect(gain, closeTo(5.5, 0.01));
    });

    test('recorta al rango del dispositivo', () {
      final gains = presetGains(
        EqualizerPreset.bassBoost,
        fiveBands,
        minDb: -3,
        maxDb: 3,
      );
      expect(gains, [3, 3, 0, 0, 0]);
      final vocal = presetGains(
        EqualizerPreset.vocal,
        fiveBands,
        minDb: -2,
        maxDb: 2,
      );
      expect(vocal.first, -2);
    });

    test('todos los preajustes con curva cubren cualquier banda', () {
      for (final preset in EqualizerPreset.values) {
        final gains = presetGains(preset, fiveBands, minDb: -15, maxDb: 15);
        expect(gains.length, 5, reason: preset.name);
      }
      expect(presetCurve(EqualizerPreset.custom), isEmpty);
    });
  });

  test('gainsFromCurve adapta valores personalizados a otras bandas', () {
    final gains = gainsFromCurve(
      const [(frequency: 100, gain: -4), (frequency: 10000, gain: 4)],
      const [100, 1000, 10000],
      minDb: -15,
      maxDb: 15,
    );
    expect(gains[0], -4);
    expect(gains[1], closeTo(0, 0.001));
    expect(gains[2], 4);
  });

  test('formatFrequency y formatGain', () {
    expect(formatFrequency(60), '60 Hz');
    expect(formatFrequency(910), '910 Hz');
    expect(formatFrequency(3600), '3.6 kHz');
    expect(formatFrequency(14000), '14 kHz');
    expect(formatFrequency(1000), '1 kHz');
    expect(formatGain(0), '0 dB');
    expect(formatGain(3), '+3 dB');
    expect(formatGain(-1.5), '-1.5 dB');
    expect(formatGain(0.04), '0 dB');
  });

  group('EqualizerSettings', () {
    test('se serializa y se recupera igual', () {
      const settings = EqualizerSettings(
        enabled: true,
        preset: EqualizerPreset.custom,
        customCurve: [(frequency: 60, gain: 2.5), (frequency: 910, gain: -1)],
        loudnessDb: 4,
      );
      final restored = EqualizerSettings.fromJson(settings.toJson());
      expect(restored.enabled, isTrue);
      expect(restored.preset, EqualizerPreset.custom);
      expect(restored.customCurve, settings.customCurve);
      expect(restored.loudnessDb, 4);
    });

    test('usa valores por defecto con datos nulos o dañados', () {
      for (final source in [null, '', '{roto', '[]', '{"preset":"otro"}']) {
        final settings = EqualizerSettings.fromJson(source);
        expect(settings.enabled, isFalse, reason: '$source');
        expect(settings.preset, EqualizerPreset.flat, reason: '$source');
      }
    });

    test('limita un refuerzo guardado fuera de rango', () {
      final settings = EqualizerSettings.fromJson('{"loudness": 99}');
      expect(settings.loudnessDb, EqualizerSettings.maxLoudnessDb);
    });
  });

  group('EqualizerController', () {
    late _FakeEngine engine;
    late MemoryKeyValueStore store;
    late EqualizerController controller;

    Future<void> start({bool ready = true}) async {
      engine = _FakeEngine(ready: ready);
      controller = EqualizerController(engine, store);
      await controller.init();
      await pumpEventQueue();
    }

    setUp(() => store = MemoryKeyValueStore());
    tearDown(() => controller.dispose());

    test(
      'arranca desactivado, plano y con las bandas del dispositivo',
      () async {
        await start();
        final state = controller.state.value;
        expect(state.isAvailable, isTrue);
        expect(state.settings.enabled, isFalse);
        expect(state.gains, [0, 0, 0, 0, 0]);
        expect(engine.enabled, isFalse);
      },
    );

    test('no está disponible hasta que el dispositivo informa', () async {
      await start(ready: false);
      expect(controller.state.value.isAvailable, isFalse);
      await controller.setBandGain(0, 5); // se ignora sin bandas
      expect(engine.bandGains, isEmpty);

      engine.becomeReady();
      await pumpEventQueue();
      expect(controller.state.value.isAvailable, isTrue);
    });

    test('activar aplica el preajuste a todas las bandas', () async {
      await start();
      await controller.selectPreset(EqualizerPreset.rock);
      await controller.setEnabled(true);
      expect(engine.enabled, isTrue);
      expect(engine.bandGains, {0: 5, 1: 3, 2: -1, 3: 3, 4: 5});
    });

    test('mover una banda pasa a Personalizado conservando el resto', () async {
      await start();
      await controller.setEnabled(true);
      await controller.selectPreset(EqualizerPreset.rock);
      await controller.setBandGain(2, 6);
      final state = controller.state.value;
      expect(state.settings.preset, EqualizerPreset.custom);
      expect(state.gains, [5, 3, 6, 3, 5]);
      expect(engine.bandGains[2], 6);
    });

    test('limita la ganancia al rango del dispositivo', () async {
      await start();
      await controller.setEnabled(true);
      await controller.setBandGain(0, 99);
      expect(controller.state.value.gains.first, 15);
    });

    test('restablecer vuelve a plano y sin refuerzo, sin desactivar', () async {
      await start();
      await controller.setEnabled(true);
      await controller.setBandGain(1, 4);
      await controller.setLoudness(6);
      await controller.reset();
      final state = controller.state.value;
      expect(state.settings.enabled, isTrue);
      expect(state.settings.preset, EqualizerPreset.flat);
      expect(state.gains, everyElement(0));
      expect(state.settings.loudnessDb, 0);
      expect(engine.loudness, 0);
    });

    test('el refuerzo se limita y no se aplica si está desactivado', () async {
      await start();
      await controller.setLoudness(50);
      expect(
        controller.state.value.settings.loudnessDb,
        EqualizerSettings.maxLoudnessDb,
      );
      expect(engine.loudness, 0, reason: 'ecualizador desactivado');
      await controller.setEnabled(true);
      expect(engine.loudness, EqualizerSettings.maxLoudnessDb);
    });

    test('persiste y restaura la configuración', () async {
      await start();
      await controller.setEnabled(true);
      await controller.selectPreset(EqualizerPreset.pop);
      await controller.setBandGain(4, -3);
      await controller.setLoudness(5);
      await controller.commit();
      await controller.dispose();

      await start(); // nuevo controlador sobre el mismo almacén
      final state = controller.state.value;
      expect(state.settings.enabled, isTrue);
      expect(state.settings.preset, EqualizerPreset.custom);
      expect(state.gains, [-1, 2, 4, 2, -3]);
      expect(state.settings.loudnessDb, 5);
      expect(engine.enabled, isTrue);
      expect(engine.bandGains[4], -3);
      expect(engine.loudness, 5);
    });

    test('elegir Personalizado sin valores parte de lo que suena', () async {
      await start();
      await controller.selectPreset(EqualizerPreset.jazz);
      await controller.selectPreset(EqualizerPreset.custom);
      expect(controller.state.value.gains, [3, 1, -1, 2, 3]);
    });
  });
}
