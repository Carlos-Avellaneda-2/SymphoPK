import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';

/// Canciones marcadas como favoritas.
abstract interface class FavoritesRepository {
  /// Ids favoritos, del más reciente al más antiguo.
  Stream<List<int>> watchIds();

  /// Alterna el estado y devuelve `true` si la canción queda como favorita.
  Future<bool> toggle(int songId);
}

class DriftFavoritesRepository implements FavoritesRepository {
  DriftFavoritesRepository(this._db);

  final AppDatabase _db;

  @override
  Stream<List<int>> watchIds() {
    final query = _db.select(_db.favorites)
      ..orderBy([
        (f) => OrderingTerm.desc(f.addedAt),
        (f) => OrderingTerm.desc(f.rowId),
      ]);
    return query.map((row) => row.songId).watch();
  }

  @override
  Future<bool> toggle(int songId) {
    return _db.transaction(() async {
      final removed = await (_db.delete(
        _db.favorites,
      )..where((f) => f.songId.equals(songId))).go();
      if (removed > 0) return false;
      await _db
          .into(_db.favorites)
          .insert(FavoritesCompanion.insert(songId: Value(songId)));
      return true;
    });
  }
}
