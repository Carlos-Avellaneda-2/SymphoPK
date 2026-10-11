import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:symphopk/core/app_info.dart';
import 'package:symphopk/features/library/domain/song.dart';
import 'package:symphopk/features/lyrics/data/lrclib_client.dart';
import 'package:symphopk/features/lyrics/domain/lrclib_match.dart';
import 'package:symphopk/features/lyrics/domain/lyrics.dart';

import '../support/songs.dart';

LrclibRecord record(
  int seconds, {
  String? synced,
  String? plain,
  bool instrumental = false,
}) => LrclibRecord(
  duration: Duration(seconds: seconds),
  syncedLyrics: synced,
  plainLyrics: plain,
  instrumental: instrumental,
);

Map<String, Object?> json(
  num duration, {
  String? synced,
  String? plain,
  bool instrumental = false,
}) => {
  'id': 1,
  'trackName': 'Tema',
  'artistName': 'Grupo',
  'albumName': 'Disco',
  'duration': duration,
  'instrumental': instrumental,
  'plainLyrics': plain,
  'syncedLyrics': synced,
};

http.Response ok(Object? body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  200,
  headers: {'content-type': 'application/json'},
);

void main() {
  const target = Duration(seconds: 200);

  group('selectBestMatch', () {
    test('elige la duración más cercana dentro de la tolerancia', () {
      final best = selectBestMatch([
        record(203, synced: '[00:01.00]lejos'),
        record(201, synced: '[00:01.00]cerca'),
        record(198, synced: '[00:01.00]medio'),
      ], target);
      expect(best!.syncedLyrics, contains('cerca'));
    });

    test('descarta lo que queda fuera de la tolerancia', () {
      expect(
        selectBestMatch([
          record(204, synced: '[00:01.00]a'),
          record(150, synced: '[00:01.00]b'),
        ], target),
        isNull,
      );
      expect(
        selectBestMatch(
          [record(204, synced: '[00:01.00]a')],
          target,
          tolerance: const Duration(seconds: 5),
        ),
        isNotNull,
      );
    });

    test('el límite de la tolerancia es inclusivo', () {
      expect(selectBestMatch([record(203, plain: 'x')], target), isNotNull);
      expect(selectBestMatch([record(197, plain: 'x')], target), isNotNull);
    });

    test('prefiere letra sincronizada aunque otra esté más cerca', () {
      final best = selectBestMatch([
        record(200, plain: 'solo texto'),
        record(202, synced: '[00:01.00]sincronizada'),
      ], target);
      expect(best!.hasSyncedLyrics, isTrue);
    });

    test('a falta de sincronizada usa texto o instrumental', () {
      expect(
        selectBestMatch([record(200, plain: 'texto')], target)!.hasPlainLyrics,
        isTrue,
      );
      expect(
        selectBestMatch([
          record(200, instrumental: true),
        ], target)!.instrumental,
        isTrue,
      );
    });

    test('ignora registros sin letra ni marca de instrumental', () {
      expect(
        selectBestMatch([record(200), record(200, synced: '  ')], target),
        isNull,
      );
      expect(selectBestMatch(const [], target), isNull);
    });

    test('sin duración conocida acepta cualquier registro útil', () {
      final best = selectBestMatch([
        record(999, plain: 'texto'),
        record(50, synced: '[00:01.00]sincronizada'),
      ], Duration.zero);
      expect(best!.hasSyncedLyrics, isTrue);
    });
  });

  group('LrclibRecord', () {
    test('lee la duración con decimales y los campos nulos', () {
      final parsed = LrclibRecord.fromJson(json(200.6));
      expect(parsed.duration, const Duration(milliseconds: 200600));
      expect(parsed.isUseful, isFalse);
      expect(parsed.toLyrics(), isNull);
    });

    test('rechaza lo que no es un objeto', () {
      expect(() => LrclibRecord.fromJson('texto'), throwsFormatException);
      expect(() => LrclibRecord.fromJson(null), throwsFormatException);
    });

    test('toLyrics prefiere sincronizada, luego texto, luego instrumental', () {
      final both = record(1, synced: '[00:01.00]a', plain: 'a').toLyrics()!;
      expect(both.isSynced, isTrue);
      expect(both.origin, LyricsOrigin.lrclib);
      expect(record(1, plain: 'a').toLyrics()!.plainText, 'a');
      expect(record(1, instrumental: true).toLyrics()!.instrumental, isTrue);
      // Sincronizada vacía: cae al texto.
      expect(record(1, synced: '', plain: 'a').toLyrics()!.plainText, 'a');
    });
  });

  group('LrclibClient', () {
    final tema = song(
      1,
      title: 'Tema',
      artist: 'Grupo',
      album: 'Disco',
      duration: target,
    );

    LrclibClient client(Future<http.Response> Function(http.Request) handler) =>
        LrclibClient(
          MockClient(handler),
          timeout: const Duration(milliseconds: 200),
        );

    test(
      'consulta /api/get con los datos de la canción y el User-Agent',
      () async {
        late http.Request sent;
        final lyrics = await client((request) async {
          sent = request;
          return ok(json(200, synced: '[00:01.00]Canción'));
        }).fetch(tema);

        expect(sent.url.host, 'lrclib.net');
        expect(sent.url.path, '/api/get');
        expect(sent.url.queryParameters, {
          'track_name': 'Tema',
          'artist_name': 'Grupo',
          'album_name': 'Disco',
          'duration': '200',
        });
        expect(sent.headers['User-Agent'], AppInfo.userAgent);
        expect(AppInfo.userAgent, contains('SymphoPK/${AppInfo.version}'));
        expect(AppInfo.userAgent, contains(AppInfo.repositoryUrl));
        expect(
          lyrics!.lines.single.text,
          'Canción',
          reason: 'decodifica UTF-8',
        );
      },
    );

    test('si /api/get responde 404 busca y elige por duración', () async {
      final paths = <String>[];
      final lyrics = await client((request) async {
        paths.add(request.url.path);
        if (request.url.path == '/api/get') return http.Response('{}', 404);
        expect(request.url.queryParameters, {
          'track_name': 'Tema',
          'artist_name': 'Grupo',
        });
        return ok([
          json(260, synced: '[00:01.00]versión en directo'),
          json(201, synced: '[00:01.00]la buena'),
        ]);
      }).fetch(tema);
      expect(paths, ['/api/get', '/api/search']);
      expect(lyrics!.lines.single.text, 'la buena');
    });

    test('si /api/get no trae letra también recurre a la búsqueda', () async {
      final lyrics = await client((request) async {
        return request.url.path == '/api/get'
            ? ok(json(200))
            : ok([json(200, plain: 'texto')]);
      }).fetch(tema);
      expect(lyrics!.plainText, 'texto');
    });

    test('devuelve null si no hay ninguna coincidencia', () async {
      expect(
        await client((request) async {
          return request.url.path == '/api/get'
              ? http.Response('{}', 404)
              : ok(<Object>[]);
        }).fetch(tema),
        isNull,
      );
      // La búsqueda también puede responder 404.
      expect(
        await client((_) async => http.Response('', 404)).fetch(tema),
        isNull,
      );
    });

    test('reconoce las canciones instrumentales', () async {
      final lyrics = await client(
        (_) async => ok(json(200, instrumental: true)),
      ).fetch(tema);
      expect(lyrics!.instrumental, isTrue);
    });

    test('omite álbum y artista desconocidos y va directo a buscar', () async {
      final requests = <Uri>[];
      Future<http.Response> handler(http.Request request) async {
        requests.add(request.url);
        return request.url.path == '/api/get'
            ? http.Response('{}', 404)
            : ok(<Object>[]);
      }

      await client(handler).fetch(
        song(1, title: 'Tema', artist: 'Grupo', album: Song.unknownAlbum),
      );
      expect(requests.first.queryParameters.containsKey('album_name'), isFalse);

      requests.clear();
      await client(handler)
          .fetch(song(2, title: 'Tema', artist: Song.unknownArtist));
      expect(requests.single.path, '/api/search');
      expect(requests.single.queryParameters, {'track_name': 'Tema'});
    });

    test('la falta de red se convierte en LyricsNetworkException', () async {
      for (final Object error in [
        const SocketException('sin red'),
        http.ClientException('conexión cerrada'),
        const HandshakeException('TLS'),
      ]) {
        await expectLater(
          client((_) async => throw error).fetch(tema),
          throwsA(isA<LyricsNetworkException>()),
          reason: '$error',
        );
      }
    });

    test('un servidor que no responde agota el tiempo de espera', () async {
      await expectLater(
        client((_) => Completer<http.Response>().future).fetch(tema),
        throwsA(isA<LyricsNetworkException>()),
      );
    });

    test('los errores del servidor son LyricsServiceException', () async {
      for (final status in [400, 429, 500, 503]) {
        await expectLater(
          client((_) async => http.Response('error', status)).fetch(tema),
          throwsA(isA<LyricsServiceException>()),
          reason: 'HTTP $status',
        );
      }
    });

    test('una respuesta que no es el JSON esperado no rompe nada', () async {
      for (final body in [
        '<html>mantenimiento</html>',
        '"texto"',
        '[1, 2]',
        '',
      ]) {
        await expectLater(
          client((request) async {
            return request.url.path == '/api/get'
                ? http.Response('{}', 404)
                : http.Response(body, 200);
          }).fetch(tema),
          throwsA(isA<LyricsServiceException>()),
          reason: body,
        );
      }
      await expectLater(
        client((_) async => http.Response('{no es json', 200)).fetch(tema),
        throwsA(isA<LyricsServiceException>()),
      );
    });
  });

  test('AppInfo.version coincide con pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version:\s*([0-9.]+)',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1);
    expect(AppInfo.version, version);
  });
}
