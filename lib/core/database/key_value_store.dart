import 'app_database.dart';

/// Almacén de ajustes clave-valor. Permite guardar preferencias sencillas
/// sin crear una tabla para cada una.
abstract interface class KeyValueStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// Implementación sobre la tabla `Settings` de Drift.
class DriftKeyValueStore implements KeyValueStore {
  DriftKeyValueStore(this._db);

  final AppDatabase _db;

  @override
  Future<String?> read(String key) {
    final query = _db.select(_db.settings)..where((s) => s.key.equals(key));
    return query.map((row) => row.value).getSingleOrNull();
  }

  @override
  Future<void> write(String key, String value) {
    return _db
        .into(_db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(key: key, value: value),
        );
  }

  @override
  Future<void> delete(String key) async {
    await (_db.delete(_db.settings)..where((s) => s.key.equals(key))).go();
  }
}
