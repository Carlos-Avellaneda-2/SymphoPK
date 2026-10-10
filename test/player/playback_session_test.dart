import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphopk/core/database/app_database.dart';
import 'package:symphopk/features/player/data/playback_session_store.dart';
import 'package:symphopk/features/player/domain/playback_session.dart';
import 'package:symphopk/features/player/domain/queue_state.dart';

import '../support/songs.dart';

void main() {
  const session = PlaybackSession(
    originalIds: [1, 2, 3, 4],
    orderIds: [3, 1, 4, 2],
    index: 2,
    shuffle: true,
    repeat: QueueRepeat.one,
    position: Duration(seconds: 42),
  );

  group('DriftPlaybackSessionStore', () {
    late AppDatabase db;
    late PlaybackSessionStore store;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      store = DriftPlaybackSessionStore(db);
    });

    tearDown(() => db.close());

    test('sin datos guardados devuelve null', () async {
      expect(await store.load(), isNull);
    });

    test('guarda y recupera la sesión completa', () async {
      await store.save(session);
      final loaded = (await store.load())!;
      expect(loaded.originalIds, [1, 2, 3, 4]);
      expect(loaded.orderIds, [3, 1, 4, 2]);
      expect(loaded.index, 2);
      expect(loaded.shuffle, isTrue);
      expect(loaded.repeat, QueueRepeat.one);
      expect(loaded.position, const Duration(seconds: 42));
    });

    test('savePosition actualiza solo la posición', () async {
      await store.save(session);
      await store.savePosition(const Duration(seconds: 90));
      final loaded = (await store.load())!;
      expect(loaded.position, const Duration(seconds: 90));
      expect(loaded.orderIds, [3, 1, 4, 2]);
    });

    test('clear borra la sesión', () async {
      await store.save(session);
      await store.clear();
      expect(await store.load(), isNull);
    });

    test('ignora datos dañados', () async {
      await db
          .into(db.settings)
          .insert(
            SettingsCompanion.insert(key: 'playback.queue', value: '{roto'),
          );
      expect(await store.load(), isNull);
    });
  });

  group('resolveSession', () {
    final all = {for (final s in songs(4)) s.id: s};

    test('con la biblioteca intacta conserva índice y posición', () {
      final resolved = resolveSession(session, all)!;
      expect(resolved.order.map((s) => s.id), [3, 1, 4, 2]);
      expect(resolved.original.map((s) => s.id), [1, 2, 3, 4]);
      expect(resolved.index, 2);
      expect(resolved.position, const Duration(seconds: 42));
    });

    test('recalcula el índice si se borró una canción anterior', () {
      final resolved = resolveSession(session, {...all}..remove(3))!;
      expect(resolved.order.map((s) => s.id), [1, 4, 2]);
      expect(resolved.order[resolved.index].id, 4);
      expect(resolved.position, const Duration(seconds: 42));
    });

    test('si se borró la canción actual empieza la siguiente desde cero', () {
      final resolved = resolveSession(session, {...all}..remove(4))!;
      expect(resolved.order[resolved.index].id, 2);
      expect(resolved.position, Duration.zero);
    });

    test('si la actual era la última y se borró, usa la anterior', () {
      final last = PlaybackSession(
        originalIds: const [1, 2],
        orderIds: const [1, 2],
        index: 1,
        shuffle: false,
        repeat: QueueRepeat.off,
        position: const Duration(seconds: 5),
      );
      final resolved = resolveSession(last, {...all}..remove(2))!;
      expect(resolved.order.single.id, 1);
      expect(resolved.index, 0);
      expect(resolved.position, Duration.zero);
    });

    test('devuelve null si no queda ninguna canción', () {
      expect(resolveSession(session, const {}), isNull);
    });
  });
}
