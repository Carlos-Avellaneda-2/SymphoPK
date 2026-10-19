import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../../core/database/key_value_store.dart';
import '../../player/domain/replay_gain.dart';

/// Preferencias generales de la app.
@immutable
class AppPreferences {
  const AppPreferences({
    this.themeMode = ThemeMode.system,
    this.saveLyricsToDisk = true,
    this.normalization = NormalizationMode.off,
    this.crossfadeSeconds = 0,
  });

  static const String themeModeKey = 'settings.theme_mode';
  static const String saveLyricsKey = 'settings.lyrics_disk_cache';
  static const String normalizationKey = 'settings.normalization';
  static const String crossfadeKey = 'settings.crossfade_seconds';

  /// Duración máxima del fundido entre canciones.
  static const int maxCrossfadeSeconds = 12;

  /// Tema de la app; por defecto sigue al del dispositivo.
  final ThemeMode themeMode;

  /// Si es `false` («No guardar letras»), las letras descargadas solo se
  /// conservan en memoria mientras la app está abierta.
  final bool saveLyricsToDisk;

  /// Normalización de volumen entre canciones (ReplayGain).
  final NormalizationMode normalization;

  /// Segundos de fundido entre canciones; 0 lo desactiva.
  final int crossfadeSeconds;

  AppPreferences copyWith({
    ThemeMode? themeMode,
    bool? saveLyricsToDisk,
    NormalizationMode? normalization,
    int? crossfadeSeconds,
  }) => AppPreferences(
    themeMode: themeMode ?? this.themeMode,
    saveLyricsToDisk: saveLyricsToDisk ?? this.saveLyricsToDisk,
    normalization: normalization ?? this.normalization,
    crossfadeSeconds: crossfadeSeconds ?? this.crossfadeSeconds,
  );

  /// Lee las preferencias guardadas; lo que falte o no sea válido queda en
  /// su valor por defecto.
  static Future<AppPreferences> load(KeyValueStore store) async {
    final theme = await store.read(themeModeKey);
    final saveLyrics = await store.read(saveLyricsKey);
    final normalization = await store.read(normalizationKey);
    final crossfade = int.tryParse(await store.read(crossfadeKey) ?? '');
    return AppPreferences(
      themeMode: ThemeMode.values.asNameMap()[theme] ?? ThemeMode.system,
      saveLyricsToDisk: saveLyrics != 'false',
      normalization:
          NormalizationMode.values.asNameMap()[normalization] ??
          NormalizationMode.off,
      crossfadeSeconds: (crossfade ?? 0).clamp(0, maxCrossfadeSeconds),
    );
  }
}

/// Preferencias leídas en `main()` antes de pintar nada, para que la app no
/// arranque con un tema y cambie a otro un instante después.
final initialPreferencesProvider = Provider<AppPreferences>(
  (ref) => const AppPreferences(),
);

final preferencesProvider =
    NotifierProvider<PreferencesController, AppPreferences>(
      PreferencesController.new,
    );

class PreferencesController extends Notifier<AppPreferences> {
  @override
  AppPreferences build() => ref.watch(initialPreferencesProvider);

  KeyValueStore get _store => ref.read(keyValueStoreProvider);

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await _store.write(AppPreferences.themeModeKey, mode.name);
  }

  Future<void> setSaveLyricsToDisk(bool value) async {
    state = state.copyWith(saveLyricsToDisk: value);
    await _store.write(AppPreferences.saveLyricsKey, '$value');
  }

  Future<void> setNormalization(NormalizationMode mode) async {
    state = state.copyWith(normalization: mode);
    await _store.write(AppPreferences.normalizationKey, mode.name);
  }

  Future<void> setCrossfadeSeconds(int seconds) async {
    final value = seconds.clamp(0, AppPreferences.maxCrossfadeSeconds);
    state = state.copyWith(crossfadeSeconds: value);
    await _store.write(AppPreferences.crossfadeKey, '$value');
  }
}
