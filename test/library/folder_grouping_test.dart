import 'package:flutter_test/flutter_test.dart';
import 'package:symphopk/features/library/data/media_store_scanner.dart';
import 'package:symphopk/features/library/domain/library_grouping.dart';

import '../support/songs.dart';

void main() {
  const music = '/storage/emulated/0/Music';

  group('groupFolders', () {
    test('agrupa por carpeta y ordena carpetas y canciones por nombre', () {
      final folders = groupFolders([
        song(1, title: 'Zulu', folder: '$music/Rock'),
        song(2, title: 'alfa', folder: '$music/salsa'),
        song(3, title: 'Bravo', folder: '$music/Rock'),
      ]);
      expect(folders.map((f) => f.name), ['Rock', 'salsa']);
      expect(folders.first.songs.map((s) => s.title), ['Bravo', 'Zulu']);
      expect(folders.first.location, 'Music');
      expect(folders.first.path, '$music/Rock');
    });

    test('no mezcla subcarpetas con su carpeta contenedora', () {
      final folders = groupFolders([
        song(1, folder: music),
        song(2, folder: '$music/Rock'),
        song(3, folder: '$music/Rock/Directos'),
      ]);
      expect(folders.map((f) => f.path), [
        '$music/Rock/Directos',
        music,
        '$music/Rock',
      ]);
      expect(folders.every((f) => f.songs.length == 1), isTrue);
    });

    test('distingue carpetas con el mismo nombre en rutas distintas', () {
      final folders = groupFolders([
        song(1, folder: '$music/Rock'),
        song(2, folder: '/storage/emulated/0/Download/Rock'),
      ]);
      expect(folders.map((f) => f.location), ['Download', 'Music']);
    });

    test('omite las canciones sin carpeta conocida', () {
      expect(groupFolders([song(1), song(2, folder: music)]).length, 1);
      expect(groupFolders([song(1)]), isEmpty);
    });
  });

  test('folderName devuelve el último segmento', () {
    expect(folderName('$music/Rock'), 'Rock');
    expect(folderName('$music/Rock/'), 'Rock');
    expect(folderName('/'), '/');
  });

  group('folderLocation', () {
    test('quita el prefijo del almacenamiento interno', () {
      expect(folderLocation('$music/Rock'), 'Music');
      expect(folderLocation('$music/Rock/Directos'), 'Music/Rock');
      expect(folderLocation(music), '');
    });

    test('conserva el identificador de una tarjeta SD', () {
      expect(
        folderLocation('/storage/1A2B-3C4D/Music/Rock'),
        '1A2B-3C4D/Music',
      );
    });
  });

  group('MediaStoreScanner.songFromRow', () {
    Map<String, Object?> row(Object? path) => {
      'id': 1,
      'uri': 'content://media/external/audio/media/1',
      'title': 'Canción',
      'durationMs': 180000,
      'path': path,
    };

    test('deriva la carpeta de la ruta del archivo', () {
      final song = MediaStoreScanner.songFromRow(row('$music/Rock/tema.mp3'))!;
      expect(song.folder, '$music/Rock');
    });

    test('deja la carpeta vacía si no hay ruta utilizable', () {
      expect(MediaStoreScanner.songFromRow(row(null))!.folder, '');
      expect(MediaStoreScanner.songFromRow(row('tema.mp3'))!.folder, '');
    });
  });
}
