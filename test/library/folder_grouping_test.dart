import 'package:flutter_test/flutter_test.dart';
import 'package:symphopk/features/library/data/media_store_scanner.dart';
import 'package:symphopk/features/library/domain/library_grouping.dart';

import '../support/songs.dart';

void main() {
  const internal = '/storage/emulated/0';
  const music = '$internal/Music';

  group('buildFolderTree', () {
    test('devuelve null si ninguna canción tiene carpeta', () {
      expect(buildFolderTree([]), isNull);
      expect(buildFolderTree([song(1)]), isNull);
    });

    test('empieza donde la música se ramifica, no en la raíz', () {
      final root = buildFolderTree([
        song(1, folder: '$music/Rock'),
        song(2, folder: '$music/Salsa'),
      ])!;
      expect(root.path, music);
      expect(root.name, 'Music');
      expect(root.subfolders.map((f) => f.name), ['Rock', 'Salsa']);
      expect(root.songs, isEmpty);
    });

    test('con una sola carpeta la raíz es esa carpeta', () {
      final root = buildFolderTree([song(1, folder: '$music/Rock')])!;
      expect(root.path, '$music/Rock');
      expect(root.subfolders, isEmpty);
      expect(root.songs.single.id, 1);
    });

    test('no salta una carpeta que tiene canciones propias', () {
      final root = buildFolderTree([
        song(1, folder: music),
        song(2, folder: '$music/Rock'),
      ])!;
      expect(root.path, music);
      expect(root.songs.single.id, 1);
      expect(root.subfolders.single.name, 'Rock');
    });

    test('anida subcarpetas y crea las intermedias sin canciones', () {
      final root = buildFolderTree([
        song(1, folder: '$music/Rock/Directos/2019'),
        song(2, folder: '$music/Salsa'),
      ])!;
      final rock = root.subfolders.first;
      expect(rock.name, 'Rock');
      expect(rock.songs, isEmpty);
      expect(rock.subfolders.single.name, 'Directos');
      expect(rock.subfolders.single.subfolders.single.songs.single.id, 1);
    });

    test(
      'ordena carpetas y canciones por nombre sin distinguir mayúsculas',
      () {
        final root = buildFolderTree([
          song(1, title: 'Zulu', folder: '$music/rock'),
          song(2, title: 'alfa', folder: '$music/rock'),
          song(3, title: 'Bravo', folder: '$music/Ambient'),
          song(4, title: 'Charlie', folder: '$music/Salsa'),
        ])!;
        expect(root.subfolders.map((f) => f.name), [
          'Ambient',
          'rock',
          'Salsa',
        ]);
        expect(root.subfolders[1].songs.map((s) => s.title), ['alfa', 'Zulu']);
      },
    );

    test('allSongs reúne las propias y después las de las subcarpetas', () {
      final root = buildFolderTree([
        song(1, title: 'B', folder: '$music/Rock/Directos'),
        song(2, title: 'A', folder: '$music/Rock'),
        song(3, title: 'C', folder: '$music/Ambient'),
        song(4, title: 'D', folder: music),
      ])!;
      expect(root.allSongs.map((s) => s.id), [4, 3, 2, 1]);
      expect(root.find('$music/Rock')!.allSongs.map((s) => s.id), [2, 1]);
      expect(root.cover!.id, 4);
    });

    test('separa el almacenamiento interno de una tarjeta SD', () {
      final root = buildFolderTree([
        song(1, folder: '$music/Rock'),
        song(2, folder: '/storage/1A2B-3C4D/Music'),
      ])!;
      expect(root.path, '/storage');
      expect(root.subfolders.map((f) => f.name), ['1A2B-3C4D', 'emulated']);
    });
  });

  group('Folder.find', () {
    final root = buildFolderTree([
      song(1, folder: '$music/Rock'),
      song(2, folder: '$music/Rock/Directos'),
      song(3, folder: '$music/Rockabilly'),
    ])!;

    test('encuentra la raíz y carpetas anidadas', () {
      expect(root.find(music), same(root));
      expect(root.find('$music/Rock/Directos')!.songs.single.id, 2);
    });

    test('no confunde carpetas cuyo nombre empieza igual', () {
      expect(root.find('$music/Rockabilly')!.songs.single.id, 3);
      expect(root.find('$music/Rock')!.songs.single.id, 1);
    });

    test('devuelve null para rutas que no existen', () {
      expect(root.find('$music/Jazz'), isNull);
      expect(root.find('/otra/ruta'), isNull);
    });
  });

  test('folderName devuelve el último segmento', () {
    expect(folderName('$music/Rock'), 'Rock');
    expect(folderName('$music/Rock/'), 'Rock');
    expect(folderName('/'), '/');
  });

  group('folderDisplayPath', () {
    test('quita el prefijo del almacenamiento interno', () {
      expect(folderDisplayPath('$music/Rock'), 'Music/Rock');
      expect(folderDisplayPath(music), 'Music');
      expect(folderDisplayPath(internal), '');
    });

    test('conserva el identificador de una tarjeta SD', () {
      expect(folderDisplayPath('/storage/1A2B-3C4D/Music'), '1A2B-3C4D/Music');
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
