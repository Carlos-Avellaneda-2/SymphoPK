import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'audio_permission_service.dart';

final audioPermissionServiceProvider = Provider<AudioPermissionService>(
  (ref) => AudioPermissionService(),
);

final audioPermissionProvider =
    AsyncNotifierProvider<AudioPermissionController, AudioPermissionStatus>(
      AudioPermissionController.new,
    );

class AudioPermissionController extends AsyncNotifier<AudioPermissionStatus> {
  AudioPermissionService get _service =>
      ref.read(audioPermissionServiceProvider);

  @override
  Future<AudioPermissionStatus> build() async {
    final status = await _service.check();
    if (status != AudioPermissionStatus.denied) return status;
    // Primer arranque: se muestra directamente el diálogo del sistema.
    return _service.request();
  }

  /// Vuelve a mostrar el diálogo del sistema.
  Future<void> request() async {
    state = await AsyncValue.guard(_service.request);
  }

  /// Relee el estado sin mostrar diálogos (p. ej. al volver de Ajustes).
  Future<void> refresh() async {
    final previous = state.value;
    state = await AsyncValue.guard(() async {
      final status = await _service.check();
      // En Android `check` nunca informa de la negación permanente (solo lo
      // hace `request`), así que se conserva la que ya conocíamos.
      if (status == AudioPermissionStatus.denied &&
          previous == AudioPermissionStatus.permanentlyDenied) {
        return AudioPermissionStatus.permanentlyDenied;
      }
      return status;
    });
  }

  Future<void> openSettings() => _service.openSettings();
}
