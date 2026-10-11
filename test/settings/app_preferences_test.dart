import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphopk/core/database/app_database.dart';
import 'package:symphopk/core/database/database_provider.dart';
import 'package:symphopk/core/database/key_value_store.dart';
import 'package:symphopk/core/utils/formatters.dart';
import 'package:symphopk/features/settings/data/app_preferences.dart';

import '../support/memory_key_value_store.dart';

void main() {
  group('AppPreferences.load', () {
    test('por defecto usa el tema del sistema y guarda letras', () async {
      final preferences = await AppPreferences.load(MemoryKeyValueStore());
      expect(preferences.themeMode, ThemeMode.system);
      expect(preferences.saveLyricsToDisk, isTrue);
    });

    test('recupera lo guardado', () async {
      final store = MemoryKeyValueStore()
        ..values[AppPreferences.themeModeKey] = 'dark'
        ..values[AppPreferences.saveLyricsKey] = 'false';
      final preferences = await AppPreferences.load(store);
      expect(preferences.themeMode, ThemeMode.dark);
      expect(preferences.saveLyricsToDisk, isFalse);
    });

    test('ignora valores no válidos', () async {
      final store = MemoryKeyValueStore()
        ..values[AppPreferences.themeModeKey] = 'fucsia'
        ..values[AppPreferences.saveLyricsKey] = 'quizá';
      final preferences = await AppPreferences.load(store);
      expect(preferences.themeMode, ThemeMode.system);
      expect(preferences.saveLyricsToDisk, isTrue);
    });
  });

  group('PreferencesController', () {
    late MemoryKeyValueStore store;
    late ProviderContainer container;

    setUp(() {
      store = MemoryKeyValueStore();
      container = ProviderContainer(
        overrides: [
          keyValueStoreProvider.overrideWithValue(store),
          initialPreferencesProvider.overrideWithValue(
            const AppPreferences(themeMode: ThemeMode.light),
          ),
        ],
      );
    });

    tearDown(() => container.dispose());

    test('arranca con las preferencias leídas en main', () {
      expect(container.read(preferencesProvider).themeMode, ThemeMode.light);
    });

    test('cambiar el tema actualiza el estado y lo persiste', () async {
      final controller = container.read(preferencesProvider.notifier);
      for (final mode in ThemeMode.values) {
        await controller.setThemeMode(mode);
        expect(container.read(preferencesProvider).themeMode, mode);
        final reloaded = await AppPreferences.load(store);
        expect(reloaded.themeMode, mode);
      }
    });

    test('«No guardar letras» se persiste sin tocar el tema', () async {
      final controller = container.read(preferencesProvider.notifier);
      await controller.setSaveLyricsToDisk(false);
      final state = container.read(preferencesProvider);
      expect(state.saveLyricsToDisk, isFalse);
      expect(state.themeMode, ThemeMode.light);
      expect((await AppPreferences.load(store)).saveLyricsToDisk, isFalse);
    });
  });

  group('DriftKeyValueStore', () {
    late AppDatabase db;
    late KeyValueStore store;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      store = DriftKeyValueStore(db);
    });

    tearDown(() => db.close());

    test('escribe, sobrescribe, lee y borra', () async {
      expect(await store.read('clave'), isNull);
      await store.write('clave', 'uno');
      await store.write('clave', 'dos');
      await store.write('otra', 'x');
      expect(await store.read('clave'), 'dos');
      await store.delete('clave');
      expect(await store.read('clave'), isNull);
      expect(await store.read('otra'), 'x');
      await store.delete('no-existe'); // no falla
    });
  });

  test('formatBytes', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(512), '512 B');
    expect(formatBytes(12 * 1024), '12 KB');
    expect(formatBytes(1024 * 1024 * 3 ~/ 2), '1.5 MB');
    expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
  });
}
