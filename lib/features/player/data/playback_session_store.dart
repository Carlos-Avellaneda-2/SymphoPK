import 'dart:convert';

import '../../../core/database/app_database.dart';
import '../domain/playback_session.dart';
import '../domain/queue_state.dart';

/// Persistencia de la última sesión de reproducción.
abstract interface class PlaybackSessionStore {
  Future<PlaybackSession?> load();

  /// Guarda cola, modos y posición.
  Future<void> save(PlaybackSession session);

  /// Actualiza solo la posición; se llama a menudo, así que evita reescribir
  /// toda la cola.
  Future<void> savePosition(Duration position);

  Future<void> clear();
}

class DriftPlaybackSessionStore implements PlaybackSessionStore {
  DriftPlaybackSessionStore(this._db);

  static const _queueKey = 'playback.queue';
  static const _positionKey = 'playback.position_ms';

  final AppDatabase _db;

  @override
  Future<PlaybackSession?> load() async {
    final queueJson = await _read(_queueKey);
    if (queueJson == null) return null;
    try {
      final data = jsonDecode(queueJson) as Map<String, dynamic>;
      final positionMs = int.tryParse(await _read(_positionKey) ?? '') ?? 0;
      return PlaybackSession(
        originalIds: (data['original'] as List).cast<int>(),
        orderIds: (data['order'] as List).cast<int>(),
        index: data['index'] as int,
        shuffle: data['shuffle'] as bool,
        repeat: QueueRepeat.values.byName(data['repeat'] as String),
        position: Duration(milliseconds: positionMs),
      );
    } on Object {
      // Datos de una versión incompatible o dañados: se empieza de cero.
      return null;
    }
  }

  @override
  Future<void> save(PlaybackSession session) {
    return _db.transaction(() async {
      await _write(
        _queueKey,
        jsonEncode({
          'original': session.originalIds,
          'order': session.orderIds,
          'index': session.index,
          'shuffle': session.shuffle,
          'repeat': session.repeat.name,
        }),
      );
      await savePosition(session.position);
    });
  }

  @override
  Future<void> savePosition(Duration position) =>
      _write(_positionKey, '${position.inMilliseconds}');

  @override
  Future<void> clear() async {
    await (_db.delete(
      _db.settings,
    )..where((s) => s.key.isIn([_queueKey, _positionKey]))).go();
  }

  Future<String?> _read(String key) {
    final query = _db.select(_db.settings)..where((s) => s.key.equals(key));
    return query.map((row) => row.value).getSingleOrNull();
  }

  Future<void> _write(String key, String value) {
    return _db
        .into(_db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(key: key, value: value),
        );
  }
}
