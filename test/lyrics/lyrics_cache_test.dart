import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:symphopk/features/library/domain/song.dart';
import 'package:symphopk/features/lyrics/data/local_lyrics_sources.dart';
import 'package:symphopk/features/lyrics/data/lrclib_client.dart';
import 'package:symphopk/features/lyrics/data/lyrics_disk_cache.dart';
import 'package:symphopk/features/lyrics/data/lyrics_repository.dart';
import 'package:symphopk/features/lyrics/domain/lyrics.dart';

import '../support/songs.dart';

Lyrics synced(String text, {LyricsOrigin origin = LyricsOrigin.lrclib}) =>
    Lyrics(
      origin: origin,
      lines: [LyricLine(const Duration(seconds: 1), text)],
    );

class _FakeLocal implements LocalLyricsSource {
  _FakeLocal(this.byId);

  final Map<int, Lyrics> byId;
  int calls = 0;

  @override
  Future<Lyrics?> find(Song song) async {
    calls++;
    return byId[song.id];
  }
}

class _FakeRemote implements RemoteLyricsSource {
  Lyrics? Function(Song song) answer = (_) => null;
  int calls = 0;

  @override
  Future<Lyrics?> fetch(Song song) async {
    calls++;
    return answer(song);
  }
}

void main() {
  late Directory temp;
  late DateTime now;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('sympho_lyrics_test');
    now = DateTime(2026, 1, 10, 12);
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  LyricsDiskCache cache({int maxBytes = 5 * 1024 * 1024}) => LyricsDiskCache(
    directory: () async => temp,
    clock: () => now,
    maxBytes: maxBytes,
  );

  group('LyricsDiskCache', () {
    test(
      'guarda y recupera letra sincronizada, texto e instrumental',
      () async {
        final disk = cache();
        await disk.write('a', synced('hola'));
        await disk.write(
          'b',
          const Lyrics(origin: LyricsOrigin.lrclib, plainText: 'texto'),
        );
        await disk.write(
          'c',
          const Lyrics(origin: LyricsOrigin.lrclib, instrumental: true),
        );

        expect(
          (await disk.read('a'))!.lines.single,
          const LyricLine(Duration(seconds: 1), 'hola'),
        );
        expect((await disk.read('b'))!.plainText, 'texto');
        expect((await disk.read('c'))!.instrumental, isTrue);
        expect(await disk.read('no-existe'), isNull);
      },
    );

    test('caduca a los 7 días sin uso', () async {
      final disk = cache();
      await disk.write('a', synced('hola'));

      now = now.add(const Duration(days: 6, hours: 23));
      expect(await disk.read('a'), isNotNull);

      // La lectura anterior renovó la caducidad: cuenta desde entonces.
      now = now.add(const Duration(days: 6));
      expect(await disk.read('a'), isNotNull, reason: 'se usó hace 6 días');

      now = now.add(const Duration(days: 7, minutes: 1));
      expect(await disk.read('a'), isNull);
      expect(await disk.sizeBytes(), 0, reason: 'el archivo caducado se borra');
    });

    test('evict borra las caducadas aunque no se lean', () async {
      final disk = cache();
      await disk.write('vieja', synced('a'));
      now = now.add(const Duration(days: 8));
      await disk.write('nueva', synced('b'));
      expect(await disk.read('vieja'), isNull);
      expect(await disk.read('nueva'), isNotNull);
      expect(Directory('${temp.path}/lyrics').listSync().length, 1);
    });

    test('al superar el límite elimina primero las menos usadas', () async {
      final entry = synced('x' * 400);
      final entrySize = encodeLyrics(entry).length;
      // Caben dos entradas, no tres.
      final disk = cache(maxBytes: entrySize * 2 + 10);

      await disk.write('primera', entry);
      now = now.add(const Duration(minutes: 1));
      await disk.write('segunda', entry);
      now = now.add(const Duration(minutes: 1));
      await disk.read('primera'); // ahora «segunda» es la menos reciente
      now = now.add(const Duration(minutes: 1));
      await disk.write('tercera', entry);

      expect(await disk.read('segunda'), isNull);
      expect(await disk.read('primera'), isNotNull);
      expect(await disk.read('tercera'), isNotNull);
      expect(await disk.sizeBytes(), lessThanOrEqualTo(entrySize * 2 + 10));
    });

    test('sizeBytes y clear', () async {
      final disk = cache();
      expect(await disk.sizeBytes(), 0);
      await disk.write('a', synced('hola'));
      await disk.write('b', synced('adiós'));
      expect(await disk.sizeBytes(), greaterThan(0));
      await disk.clear();
      expect(await disk.sizeBytes(), 0);
      expect(await disk.read('a'), isNull);
      await disk.clear(); // vaciar dos veces no falla
    });

    test('un archivo dañado se descarta sin lanzar', () async {
      final disk = cache();
      await disk.write('a', synced('hola'));
      File('${temp.path}/lyrics/a.json').writeAsStringSync('{roto');
      expect(await disk.read('a'), isNull);
      expect(File('${temp.path}/lyrics/a.json').existsSync(), isFalse);
    });

    test('un directorio inaccesible no rompe la caché', () async {
      final blocked = File('${temp.path}/archivo')..writeAsStringSync('x');
      final disk = LyricsDiskCache(
        directory: () async => Directory(blocked.path),
      );
      await disk.write('a', synced('hola')); // no puede crear la carpeta
      expect(await disk.read('a'), isNull);
      expect(await disk.sizeBytes(), 0);
    });
  });

  group('lyricsCacheKey', () {
    test('es estable y sirve como nombre de archivo', () {
      final key = lyricsCacheKey(song(1, title: 'Tema', artist: 'Grupo'));
      expect(key, lyricsCacheKey(song(99, title: 'tema', artist: 'GRUPO')));
      expect(key, matches(RegExp(r'^[0-9a-f]{16}$')));
    });

    test('cambia con el título, el artista, el álbum o la duración', () {
      final base = song(1, title: 'Tema', artist: 'Grupo', album: 'Disco');
      final keys = {
        lyricsCacheKey(base),
        lyricsCacheKey(song(1, title: 'Otro', artist: 'Grupo', album: 'Disco')),
        lyricsCacheKey(song(1, title: 'Tema', artist: 'Otro', album: 'Disco')),
        lyricsCacheKey(song(1, title: 'Tema', artist: 'Grupo', album: 'Otro')),
        lyricsCacheKey(
          song(
            1,
            title: 'Tema',
            artist: 'Grupo',
            album: 'Disco',
            duration: const Duration(minutes: 4),
          ),
        ),
      };
      expect(keys.length, 5);
    });
  });

  group('LyricsRepository', () {
    late _FakeRemote remote;
    late bool diskEnabled;

    LyricsRepository repository({
      List<LocalLyricsSource> local = const [],
      List<LocalLyricsSource> fallback = const [],
    }) => LyricsRepository(
      localSources: local,
      fallbackSources: fallback,
      remote: remote,
      diskCache: cache(),
      diskCacheEnabled: () => diskEnabled,
    );

    setUp(() {
      remote = _FakeRemote();
      diskEnabled = true;
    });

    group('prioridad de las fuentes', () {
      const plainEmbedded = Lyrics(
        origin: LyricsOrigin.embedded,
        plainText: 'letra del archivo',
      );
      const plainOnline = Lyrics(
        origin: LyricsOrigin.lrclib,
        plainText: 'letra de LRCLIB',
      );

      Lyrics found(LyricsResult result) => (result as LyricsFound).lyrics;

      test('el .lrc va antes que todo y no consulta la red', () async {
        final lrc = _FakeLocal({
          1: synced('lrc', origin: LyricsOrigin.lrcFile),
        });
        final embedded = _FakeLocal({1: plainEmbedded});
        remote.answer = (_) => synced('remota');
        final repo = repository(local: [lrc], fallback: [embedded]);

        expect(
          found(await repo.lyricsFor(song(1))).origin,
          LyricsOrigin.lrcFile,
        );
        expect(remote.calls, 0);
        expect(embedded.calls, 0);
      });

      test('LRCLIB sincronizada gana a la letra incrustada', () async {
        // El caso que motivó el cambio: el archivo trae la letra como texto
        // y LRCLIB la tiene sincronizada.
        final embedded = _FakeLocal({1: plainEmbedded});
        remote.answer = (_) => synced('remota');
        final repo = repository(fallback: [embedded]);

        final lyrics = found(await repo.lyricsFor(song(1)));
        expect(lyrics.origin, LyricsOrigin.lrclib);
        expect(lyrics.isSynced, isTrue);
        expect(embedded.calls, 0, reason: 'no hace falta leer el archivo');
      });

      test('gana también a una incrustada sincronizada', () async {
        final embedded = _FakeLocal({
          1: synced('incrustada', origin: LyricsOrigin.embedded),
        });
        remote.answer = (_) => synced('remota');
        final repo = repository(fallback: [embedded]);
        expect(
          found(await repo.lyricsFor(song(1))).origin,
          LyricsOrigin.lrclib,
        );
      });

      test('si LRCLIB no la tiene, usa la incrustada', () async {
        final embedded = _FakeLocal({1: plainEmbedded});
        remote.answer = (_) => null;
        final repo = repository(fallback: [embedded]);

        final lyrics = found(await repo.lyricsFor(song(1)));
        expect(lyrics.origin, LyricsOrigin.embedded);
        expect(lyrics.plainText, 'letra del archivo');
      });

      test(
        'si LRCLIB solo tiene texto, una incrustada con tiempos gana',
        () async {
          final embedded = _FakeLocal({
            1: synced('incrustada', origin: LyricsOrigin.embedded),
          });
          remote.answer = (_) => plainOnline;
          final repo = repository(fallback: [embedded]);
          expect(
            found(await repo.lyricsFor(song(1))).origin,
            LyricsOrigin.embedded,
          );
        },
      );

      test(
        'entre dos letras de solo texto se queda con la de LRCLIB',
        () async {
          final embedded = _FakeLocal({1: plainEmbedded});
          remote.answer = (_) => plainOnline;
          final repo = repository(fallback: [embedded]);
          expect(
            found(await repo.lyricsFor(song(1))).origin,
            LyricsOrigin.lrclib,
          );
        },
      );

      test('si LRCLIB la marca instrumental pero el archivo trae letra, la muestra', () async {
        final embedded = _FakeLocal({1: plainEmbedded});
        remote.answer = (_) =>
            const Lyrics(origin: LyricsOrigin.lrclib, instrumental: true);
        final repo = repository(fallback: [embedded]);
        expect(
          found(await repo.lyricsFor(song(1))).origin,
          LyricsOrigin.embedded,
        );
      });

      test(
        'sin conexión muestra la incrustada y reintenta más tarde',
        () async {
          final embedded = _FakeLocal({1: plainEmbedded});
          remote.answer = (_) => throw const LyricsNetworkException('sin red');
          final repo = repository(fallback: [embedded]);

          expect(
            found(await repo.lyricsFor(song(1))).origin,
            LyricsOrigin.embedded,
          );

          // Al volver la conexión debe encontrar la sincronizada.
          remote.answer = (_) => synced('remota');
          final later = found(await repo.lyricsFor(song(1)));
          expect(later.origin, LyricsOrigin.lrclib);
          expect(later.isSynced, isTrue);
        },
      );

      test('si el servicio falla también recurre a la incrustada', () async {
        final embedded = _FakeLocal({1: plainEmbedded});
        remote.answer = (_) => throw const LyricsServiceException('HTTP 500');
        final repo = repository(fallback: [embedded]);
        expect(
          found(await repo.lyricsFor(song(1))).origin,
          LyricsOrigin.embedded,
        );
      });

      test(
        'sin conexión y sin incrustada sigue avisando de la conexión',
        () async {
          remote.answer = (_) => throw const LyricsNetworkException('sin red');
          final repo = repository(fallback: [_FakeLocal({})]);
          expect(await repo.lyricsFor(song(1)), isA<LyricsOffline>());
        },
      );

      test('sin ninguna fuente con letra, no encontrada', () async {
        final repo = repository(fallback: [_FakeLocal({})]);
        expect(await repo.lyricsFor(song(1)), isA<LyricsNotFound>());
      });

      test('la letra incrustada nunca se copia a la caché en disco', () async {
        final embedded = _FakeLocal({1: plainEmbedded});
        await repository(fallback: [embedded]).lyricsFor(song(1));
        expect(await cache().sizeBytes(), 0);
      });

      test('una letra de LRCLIB ya en caché evita leer el archivo', () async {
        remote.answer = (_) => synced('remota');
        await repository().lyricsFor(song(1, title: 'Tema'));

        // Nueva sesión, sin red: la caché en disco basta.
        final embedded = _FakeLocal({1: plainEmbedded});
        remote.answer = (_) => throw const LyricsNetworkException('sin red');
        final lyrics = found(
          await repository(fallback: [embedded])
              .lyricsFor(song(1, title: 'Tema')),
        );
        expect(lyrics.origin, LyricsOrigin.lrclib);
        expect(embedded.calls, 0);
      });
    });
    test('la memoria evita repetir la búsqueda en la misma sesión', () async {
      final local = _FakeLocal({});
      remote.answer = (_) => synced('remota');
      final repo = repository(local: [local]);
      await repo.lyricsFor(song(1));
      await repo.lyricsFor(song(1));
      expect(local.calls, 1);
      expect(remote.calls, 1);
    });

    test('dos peticiones simultáneas comparten una sola consulta', () async {
      remote.answer = (_) => synced('remota');
      final repo = repository();
      await Future.wait([repo.lyricsFor(song(1)), repo.lyricsFor(song(1))]);
      expect(remote.calls, 1);
    });

    test('lo descargado se guarda en disco y sirve en otra sesión', () async {
      remote.answer = (_) => synced('remota');
      await repository().lyricsFor(song(1, title: 'Tema'));
      expect(await cache().sizeBytes(), greaterThan(0));

      remote.answer = (_) => throw const LyricsNetworkException('sin red');
      final result = await repository().lyricsFor(song(1, title: 'Tema'));
      expect(result, isA<LyricsFound>());
      expect(remote.calls, 1, reason: 'la segunda sesión no usa la red');
    });

    test('con «No guardar letras» no se escribe ni se lee del disco', () async {
      remote.answer = (_) => synced('remota');
      diskEnabled = false;
      await repository().lyricsFor(song(1));
      expect(await cache().sizeBytes(), 0);

      // Aunque exista una copia en disco, se ignora.
      await cache().write(lyricsCacheKey(song(2)), synced('en disco'));
      remote.answer = (_) => synced('de la red');
      final result = await repository().lyricsFor(song(2)) as LyricsFound;
      expect(result.lyrics.lines.single.text, 'de la red');
    });

    test('las letras locales no se copian al disco', () async {
      final local = _FakeLocal({
        1: synced('lrc', origin: LyricsOrigin.lrcFile),
      });
      await repository(local: [local]).lyricsFor(song(1));
      expect(await cache().sizeBytes(), 0);
    });

    test('distingue instrumental y no encontrada, y las recuerda', () async {
      remote.answer = (song) => song.id == 1
          ? const Lyrics(origin: LyricsOrigin.lrclib, instrumental: true)
          : null;
      final repo = repository();
      expect(await repo.lyricsFor(song(1)), isA<LyricsInstrumental>());
      expect(await repo.lyricsFor(song(2)), isA<LyricsNotFound>());
      expect(await repo.lyricsFor(song(2)), isA<LyricsNotFound>());
      expect(remote.calls, 2, reason: 'no vuelve a preguntar por la misma');
    });

    test('sin conexión devuelve LyricsOffline y permite reintentar', () async {
      remote.answer = (_) => throw const LyricsNetworkException('sin red');
      final repo = repository();
      expect(await repo.lyricsFor(song(1)), isA<LyricsOffline>());

      remote.answer = (_) => synced('ya hay red');
      expect(await repo.lyricsFor(song(1)), isA<LyricsFound>());
    });

    test(
      'cualquier otro fallo es LyricsUnavailable, nunca una excepción',
      () async {
        final repo = repository();
        for (final Object error in [
          const LyricsServiceException('HTTP 500'),
          StateError('inesperado'),
          const FormatException('json'),
        ]) {
          remote.answer = (_) => throw error;
          expect(
            await repo.lyricsFor(song(1)),
            isA<LyricsUnavailable>(),
            reason: '$error',
          );
        }
      },
    );

    test('prefetch deja la letra lista y no propaga errores', () async {
      remote.answer = (_) => synced('remota');
      final repo = repository();
      await repo.prefetch(song(1));
      expect(remote.calls, 1);
      await repo.lyricsFor(song(1));
      expect(remote.calls, 1, reason: 'ya estaba en memoria');

      remote.answer = (_) => throw StateError('x');
      await repo.prefetch(song(2)); // no lanza
    });

    test('clearMemory obliga a buscar de nuevo', () async {
      final local = _FakeLocal({});
      final repo = repository(local: [local]);
      await repo.lyricsFor(song(1));
      repo.clearMemory();
      local.byId[1] = synced('nuevo .lrc', origin: LyricsOrigin.lrcFile);
      final result = await repo.lyricsFor(song(1)) as LyricsFound;
      expect(result.lyrics.origin, LyricsOrigin.lrcFile);
    });

    test('la memoria tiene un tamaño máximo', () async {
      remote.answer = (_) => synced('remota');
      diskEnabled = false;
      final repo = LyricsRepository(
        localSources: const [],
        remote: remote,
        diskCache: cache(),
        diskCacheEnabled: () => false,
        memoryCapacity: 2,
      );
      await repo.lyricsFor(song(1));
      await repo.lyricsFor(song(2));
      await repo.lyricsFor(song(3)); // expulsa la 1
      await repo.lyricsFor(song(1));
      expect(remote.calls, 4);
    });
  });
}
