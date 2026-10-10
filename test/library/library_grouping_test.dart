import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:symphopk/core/utils/formatters.dart';
import 'package:symphopk/features/library/data/artwork_repository.dart';
import 'package:symphopk/features/library/data/library_scanner.dart';
import 'package:symphopk/features/library/domain/library_grouping.dart';
import 'package:symphopk/features/library/domain/song.dart';

import '../support/songs.dart';

class _FakeScanner implements LibraryScanner {
  int calls = 0;

  @override
  Future<Uint8List?> artwork(int songId, {int size = 600}) async {
    calls++;
    return songId.isEven ? Uint8List.fromList([songId]) : null;
  }

  @override
  Future<List<Song>> scanSongs() async => const [];
}

void main() {
  final library = [
    song(
      1,
      title: 'Bravo',
      artist: 'Zeta',
      album: 'Uno',
      albumId: 10,
      artistId: 1,
      track: 2,
    ),
    song(
      2,
      title: 'alfa',
      artist: 'Zeta',
      album: 'Uno',
      albumId: 10,
      artistId: 1,
      track: 1,
    ),
    song(
      3,
      title: 'Charlie',
      artist: 'Beta',
      album: 'Dos',
      albumId: 20,
      artistId: 2,
    ),
    song(
      4,
      title: 'Delta',
      artist: 'Zeta',
      album: 'Dos',
      albumId: 20,
      artistId: 1,
    ),
  ];

  group('groupAlbums', () {
    test('agrupa por álbum, ordena por nombre y por pista', () {
      final albums = groupAlbums(library);
      expect(albums.map((a) => a.name), ['Dos', 'Uno']);
      expect(albums.last.songs.map((s) => s.id), [2, 1]);
    });

    test('marca varios artistas cuando el álbum es compartido', () {
      final albums = groupAlbums(library);
      expect(albums.first.artist, 'Varios artistas');
      expect(albums.last.artist, 'Zeta');
    });
  });

  test('groupArtists cuenta canciones y álbumes por artista', () {
    final artists = groupArtists(library);
    expect(artists.map((a) => a.name), ['Beta', 'Zeta']);
    expect(artists.last.songs.map((s) => s.title), ['alfa', 'Bravo', 'Delta']);
    expect(artists.last.albumCount, 2);
  });

  group('searchSongs', () {
    test('busca por título o artista sin distinguir mayúsculas', () {
      expect(searchSongs(library, 'ALF').map((s) => s.id), [2]);
      expect(searchSongs(library, 'beta').map((s) => s.id), [3]);
    });

    test('la consulta vacía devuelve todo', () {
      expect(searchSongs(library, '  '), library);
    });
  });

  group('ArtworkRepository', () {
    test('no repite la consulta de una carátula ya cargada', () async {
      final scanner = _FakeScanner();
      final repository = ArtworkRepository(scanner);
      expect(await repository.load(2, size: 200), isNotNull);
      expect(await repository.load(2, size: 200), isNotNull);
      expect(scanner.calls, 1);
      // También se recuerda que una canción no tiene carátula.
      expect(await repository.load(1, size: 200), isNull);
      expect(repository.isCached(1, 200), isTrue);
    });

    test('descarta la entrada usada hace más tiempo al llenarse', () async {
      final repository = ArtworkRepository(_FakeScanner(), capacity: 2);
      await repository.load(2, size: 200);
      await repository.load(4, size: 200);
      await repository.load(2, size: 200); // 2 pasa a ser la más reciente
      await repository.load(6, size: 200);
      expect(repository.isCached(4, 200), isFalse);
      expect(repository.isCached(2, 200), isTrue);
    });
  });

  test('formatDuration', () {
    expect(formatDuration(const Duration(seconds: 5)), '0:05');
    expect(formatDuration(const Duration(minutes: 3, seconds: 7)), '3:07');
    expect(
      formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
      '1:02:03',
    );
  });
}
