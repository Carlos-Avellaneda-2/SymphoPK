import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/playlist.dart';

/// Listas de reproducción del usuario.
abstract interface class PlaylistRepository {
  /// Todas las listas, ordenadas por nombre.
  Stream<List<Playlist>> watchAll();

  Stream<Playlist?> watch(int id);

  /// Crea una lista y devuelve su id. Lanza [ArgumentError] si el nombre
  /// queda vacío.
  Future<int> create(String name);

  Future<void> rename(int id, String name);

  Future<void> delete(int id);

  /// Añade al final. Devuelve `false` si la canción ya estaba en la lista.
  Future<bool> addSong(int playlistId, int songId);

  Future<void> removeSong(int playlistId, int songId);

  /// Mueve la canción de la posición [from] a [to] (índice final).
  Future<void> moveSong(int playlistId, int from, int to);
}

class DriftPlaylistRepository implements PlaylistRepository {
  DriftPlaylistRepository(this._db);

  final AppDatabase _db;

  JoinedSelectStatement<HasResultSet, dynamic> _joined() {
    return _db.select(_db.playlists).join([
      leftOuterJoin(
        _db.playlistSongs,
        _db.playlistSongs.playlistId.equalsExp(_db.playlists.id),
      ),
    ])..orderBy([
      OrderingTerm.asc(_db.playlists.name.lower()),
      OrderingTerm.asc(_db.playlists.id),
      OrderingTerm.asc(_db.playlistSongs.position),
    ]);
  }

  /// Agrupa las filas del join (una por canción) en listas.
  List<Playlist> _group(List<TypedResult> rows) {
    final order = <int>[];
    final headers = <int, PlaylistRow>{};
    final songs = <int, List<int>>{};
    for (final row in rows) {
      final playlist = row.readTable(_db.playlists);
      if (!headers.containsKey(playlist.id)) {
        headers[playlist.id] = playlist;
        order.add(playlist.id);
        songs[playlist.id] = [];
      }
      final song = row.readTableOrNull(_db.playlistSongs);
      if (song != null) songs[playlist.id]!.add(song.songId);
    }
    return [
      for (final id in order)
        Playlist(
          id: id,
          name: headers[id]!.name,
          songIds: List.unmodifiable(songs[id]!),
          createdAt: headers[id]!.createdAt,
        ),
    ];
  }

  @override
  Stream<List<Playlist>> watchAll() => _joined().watch().map(_group);

  @override
  Stream<Playlist?> watch(int id) {
    final query = _joined()..where(_db.playlists.id.equals(id));
    return query.watch().map((rows) => _group(rows).firstOrNull);
  }

  @override
  Future<int> create(String name) {
    return _db
        .into(_db.playlists)
        .insert(PlaylistsCompanion.insert(name: _validName(name)));
  }

  @override
  Future<void> rename(int id, String name) async {
    await (_db.update(_db.playlists)..where((p) => p.id.equals(id))).write(
      PlaylistsCompanion(name: Value(_validName(name))),
    );
  }

  @override
  Future<void> delete(int id) async {
    await (_db.delete(_db.playlists)..where((p) => p.id.equals(id))).go();
  }

  @override
  Future<bool> addSong(int playlistId, int songId) {
    return _db.transaction(() async {
      final ids = await _songIds(playlistId);
      if (ids.contains(songId)) return false;
      final maxPosition = _db.playlistSongs.position.max();
      final last =
          await (_db.selectOnly(_db.playlistSongs)
                ..addColumns([maxPosition])
                ..where(_db.playlistSongs.playlistId.equals(playlistId)))
              .map((row) => row.read(maxPosition))
              .getSingle();
      await _db
          .into(_db.playlistSongs)
          .insert(
            PlaylistSongsCompanion.insert(
              playlistId: playlistId,
              songId: songId,
              position: (last ?? -1) + 1,
            ),
          );
      return true;
    });
  }

  @override
  Future<void> removeSong(int playlistId, int songId) async {
    await (_db.delete(_db.playlistSongs)..where(
          (s) => s.playlistId.equals(playlistId) & s.songId.equals(songId),
        ))
        .go();
  }

  @override
  Future<void> moveSong(int playlistId, int from, int to) {
    return _db.transaction(() async {
      final ids = await _songIds(playlistId);
      if (from < 0 || from >= ids.length || to < 0 || to >= ids.length) return;
      ids.insert(to, ids.removeAt(from));
      // Se renumeran todas las posiciones: las listas son pequeñas y así no
      // quedan huecos ni empates.
      await _db.batch((batch) {
        for (var i = 0; i < ids.length; i++) {
          batch.update(
            _db.playlistSongs,
            PlaylistSongsCompanion(position: Value(i)),
            where: (s) =>
                s.playlistId.equals(playlistId) & s.songId.equals(ids[i]),
          );
        }
      });
    });
  }

  Future<List<int>> _songIds(int playlistId) {
    final query = _db.select(_db.playlistSongs)
      ..where((s) => s.playlistId.equals(playlistId))
      ..orderBy([(s) => OrderingTerm.asc(s.position)]);
    return query.map((row) => row.songId).get();
  }

  String _validName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'El nombre no puede estar vacío');
    }
    return trimmed.length > 100 ? trimmed.substring(0, 100) : trimmed;
  }
}
