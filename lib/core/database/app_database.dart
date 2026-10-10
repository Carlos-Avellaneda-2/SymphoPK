import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

// Las canciones no se guardan aquí: viven en MediaStore y se referencian
// por su id. La base de datos solo contiene lo que el usuario crea.

@DataClassName('PlaylistRow')
class Playlists extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('PlaylistSongRow')
class PlaylistSongs extends Table {
  IntColumn get playlistId =>
      integer().references(Playlists, #id, onDelete: KeyAction.cascade)();
  IntColumn get songId => integer()();

  /// Orden de la canción dentro de la lista.
  IntColumn get position => integer()();

  @override
  Set<Column> get primaryKey => {playlistId, songId};
}

@DataClassName('FavoriteRow')
class Favorites extends Table {
  IntColumn get songId => integer()();
  DateTimeColumn get addedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {songId};
}

/// Pares clave-valor para el estado de la sesión (última canción, etc.).
@DataClassName('SettingRow')
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [Playlists, PlaylistSongs, Favorites, Settings])
class AppDatabase extends _$AppDatabase {
  /// Sin argumentos abre el archivo de la app; los tests pasan una base de
  /// datos en memoria.
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'symphopk'));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (details) async {
      // SQLite no aplica las claves foráneas (ni el borrado en cascada) si
      // no se activan en cada conexión.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
