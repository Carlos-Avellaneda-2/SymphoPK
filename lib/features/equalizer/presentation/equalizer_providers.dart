import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/equalizer_controller.dart';

/// Controlador del ecualizador. Se crea en `main()` junto al reproductor
/// (los efectos deben existir antes que él) y se inyecta con un override.
final equalizerControllerProvider = Provider<EqualizerController>(
  (ref) => throw UnimplementedError('equalizerControllerProvider sin override'),
);

final equalizerStateProvider = StreamProvider<EqualizerState>(
  (ref) => ref.watch(equalizerControllerProvider).state,
);
