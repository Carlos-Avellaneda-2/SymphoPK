import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphopk/core/database/app_database.dart';
import 'package:symphopk/features/favorites/data/favorites_repository.dart';
import 'package:symphopk/features/playlists/data/playlist_repository.dart';

void main() {
  late AppDatabase db;
  late PlaylistRepository playlists;
  late FavoritesRepository favorites;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    playlists = DriftPlaylistRepository(db);
    favorites = DriftFavoritesRepository(db);
  });

  tearDown(() => db.close());

  group('PlaylistRepository', () {
    test('crea listas y las devuelve ordenadas por nombre', () async {
      await playlists.create('Rock');
      await playlists.create('  ambient  ');
      final all = await playlists.watchAll().first;
      expect(all.map((p) => p.name), ['ambient', 'Rock']);
      expect(all.every((p) => p.songIds.isEmpty), isTrue);
    });

    test('rechaza nombres vacíos al crear y al renombrar', () async {
      expect(() => playlists.create('   '), throwsArgumentError);
      final id = await playlists.create('Rock');
      expect(() => playlists.rename(id, ''), throwsArgumentError);
    });

    test('renombra una lista', () async {
      final id = await playlists.create('Rock');
      await playlists.rename(id, 'Rock clásico');
      expect((await playlists.watch(id).first)!.name, 'Rock clásico');
    });

    test('añade canciones al final y conserva el orden', () async {
      final id = await playlists.create('Rock');
      expect(await playlists.addSong(id, 30), isTrue);
      expect(await playlists.addSong(id, 10), isTrue);
      expect(await playlists.addSong(id, 20), isTrue);
      expect((await playlists.watch(id).first)!.songIds, [30, 10, 20]);
    });

    test('no duplica una canción ya presente', () async {
      final id = await playlists.create('Rock');
      await playlists.addSong(id, 1);
      expect(await playlists.addSong(id, 1), isFalse);
      expect((await playlists.watch(id).first)!.songIds, [1]);
    });

    test('la misma canción puede estar en varias listas', () async {
      final a = await playlists.create('A');
      final b = await playlists.create('B');
      expect(await playlists.addSong(a, 1), isTrue);
      expect(await playlists.addSong(b, 1), isTrue);
    });

    test('quita canciones y sigue añadiendo al final', () async {
      final id = await playlists.create('Rock');
      for (final song in [1, 2, 3]) {
        await playlists.addSong(id, song);
      }
      await playlists.removeSong(id, 2);
      await playlists.addSong(id, 4);
      expect((await playlists.watch(id).first)!.songIds, [1, 3, 4]);
    });

    test('mueve canciones dentro de la lista', () async {
      final id = await playlists.create('Rock');
      for (final song in [1, 2, 3, 4]) {
        await playlists.addSong(id, song);
      }
      await playlists.moveSong(id, 0, 2);
      expect((await playlists.watch(id).first)!.songIds, [2, 3, 1, 4]);
      await playlists.moveSong(id, 3, 0);
      expect((await playlists.watch(id).first)!.songIds, [4, 2, 3, 1]);
      await playlists.moveSong(id, 9, 0); // fuera de rango: sin cambios
      expect((await playlists.watch(id).first)!.songIds, [4, 2, 3, 1]);
    });

    test('eliminar una lista borra también sus canciones', () async {
      final id = await playlists.create('Rock');
      await playlists.addSong(id, 1);
      await playlists.delete(id);
      expect(await playlists.watch(id).first, isNull);
      expect(await db.select(db.playlistSongs).get(), isEmpty);
    });

    test('watchAll emite al cambiar el contenido de una lista', () async {
      final id = await playlists.create('Rock');
      final emissions = <List<int>>[];
      final subscription = playlists.watchAll().listen(
        (all) => emissions.add(all.single.songIds),
      );
      await pumpEventQueue();
      await playlists.addSong(id, 5);
      await pumpEventQueue();
      await subscription.cancel();
      expect(emissions.first, isEmpty);
      expect(emissions.last, [5]);
    });
  });

  group('FavoritesRepository', () {
    test('toggle marca y desmarca', () async {
      expect(await favorites.toggle(7), isTrue);
      expect(await favorites.watchIds().first, [7]);
      expect(await favorites.toggle(7), isFalse);
      expect(await favorites.watchIds().first, isEmpty);
    });

    test('devuelve primero el favorito más reciente', () async {
      await favorites.toggle(1);
      await favorites.toggle(2);
      await favorites.toggle(3);
      expect(await favorites.watchIds().first, [3, 2, 1]);
    });
  });
}
