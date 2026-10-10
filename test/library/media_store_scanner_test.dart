import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphopk/features/library/data/media_store_scanner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(MediaStoreScanner.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Map<String, Object?> row(int id, {Object? durationMs = 180000}) => {
    'id': id,
    'uri': 'content://media/external/audio/media/$id',
    'title': 'Canción $id',
    'displayName': 'cancion_$id.mp3',
    'artist': 'Artista',
    'artistId': 7,
    'album': 'Álbum',
    'albumId': 9,
    'track': 3,
    'dateAdded': 1700000000,
    'durationMs': durationMs,
  };

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('scanSongs convierte las filas y descarta clips cortos', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'querySongs');
      return [row(1), row(2, durationMs: 5000), row(3)];
    });
    final songs = await MediaStoreScanner().scanSongs();
    expect(songs.map((s) => s.id), [1, 3]);
    expect(songs.first.title, 'Canción 1');
    expect(songs.first.duration, const Duration(minutes: 3));
    expect(songs.first.albumId, 9);
    expect(songs.first.uri, 'content://media/external/audio/media/1');
  });

  test(
    'artwork envía id y tamaño, y trata los bytes vacíos como null',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        final id = (call.arguments as Map)['id'] as int;
        return id == 1 ? Uint8List.fromList([1, 2, 3]) : Uint8List(0);
      });
      final scanner = MediaStoreScanner();
      expect(await scanner.artwork(1, size: 200), [1, 2, 3]);
      expect(await scanner.artwork(2, size: 200), isNull);
      expect(calls.first.arguments, {'id': 1, 'size': 200});
    },
  );

  group('songFromRow', () {
    test('sustituye etiquetas vacías o desconocidas', () {
      final song = MediaStoreScanner.songFromRow({
        ...row(1),
        'title': '  ',
        'artist': '<unknown>',
        'album': null,
      })!;
      expect(song.title, 'cancion_1', reason: 'usa el nombre de archivo');
      expect(song.artist, 'Artista desconocido');
      expect(song.album, 'Álbum desconocido');
    });

    test('tolera campos opcionales nulos', () {
      final song = MediaStoreScanner.songFromRow({
        ...row(1),
        'albumId': null,
        'artistId': null,
        'track': null,
        'durationMs': null,
      })!;
      expect(song.albumId, isNull);
      expect(song.duration, Duration.zero);
    });

    test('descarta filas sin id o sin uri', () {
      expect(MediaStoreScanner.songFromRow({...row(1), 'id': null}), isNull);
      expect(MediaStoreScanner.songFromRow({...row(1), 'uri': null}), isNull);
    });
  });
}
