import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_database.dart';
import 'key_value_store.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});

/// Ajustes sencillos de la app guardados en la tabla `Settings`.
final keyValueStoreProvider = Provider<KeyValueStore>(
  (ref) => DriftKeyValueStore(ref.watch(appDatabaseProvider)),
);
