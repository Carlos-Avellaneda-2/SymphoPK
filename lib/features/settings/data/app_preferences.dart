import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../../core/database/key_value_store.dart';

/// Preferencias generales de la app.
@immutable
class AppPreferences {
  const AppPreferences({
    this.themeMode = ThemeMode.system,
    this.saveLyricsToDisk = true,
  });

  static const String themeModeKey = 'settings.theme_mode';
  static const String saveLyricsKey = 'settings.lyrics_disk_cache';

  /// Tema de la app; por defecto sigue al del dispositivo.
  final ThemeMode themeMode;

  /// Si es `false` («No guardar letras»), las letras descargadas solo se
  /// conservan en memoria mientras la app está abierta.
  final bool saveLyricsToDisk;

  AppPreferences copyWith({ThemeMode? themeMode, bool? saveLyricsToDisk}) =>
      AppPreferences(
        themeMode: themeMode ?? this.themeMode,
        saveLyricsToDisk: saveLyricsToDisk ?? this.saveLyricsToDisk,
      );

  /// Lee las preferencias guardadas; lo que falte o no sea válido queda en
  /// su valor por defecto.
  static Future<AppPreferences> load(KeyValueStore store) async {
    final theme = await store.read(themeModeKey);
    final saveLyrics = await store.read(saveLyricsKey);
    return AppPreferences(
      themeMode: ThemeMode.values.asNameMap()[theme] ?? ThemeMode.system,
      saveLyricsToDisk: saveLyrics != 'false',
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
}
