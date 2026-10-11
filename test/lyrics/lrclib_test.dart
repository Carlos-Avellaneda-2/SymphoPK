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

/// Registro de prueba. La letra sincronizada lleva [label] para poder
/// comprobar cuál se eligió.
LrclibRecord record(
  num seconds, {
  String title = 'Tema',
  String artist = 'Grupo',
  String? label,
  bool synced = true,
  String? plain,
  bool instrumental = false,
}) => LrclibRecord(
  trackName: title,
  artistName: artist,
  duration: Duration(milliseconds: (seconds * 1000).round()),
  syncedLyrics: synced && !instrumental
      ? '[00:01.00]${label ?? '$seconds'}'
      : null,
  plainLyrics: plain,
  instrumental: instrumental,
);

Map<String, Object?> json(
  num duration, {
  String title = 'Tema',
  String artist = 'Grupo',
  String? synced,
  String? plain,
  bool instrumental = false,
}) => {
  'id': 1,
  'trackName': title,
  'artistName': artist,
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

/// Texto de la única línea de la letra elegida.
String? picked(LrclibRecord? best) => best?.toLyrics()?.lines.single.text;

void main() {
  const target = Duration(seconds: 200);

  LrclibRecord? select(
    List<LrclibRecord> records, {
    String title = 'Tema',
    String? artist = 'Grupo',
    Duration duration = target,
    Duration tolerance = const Duration(seconds: 3),
  }) => selectBestMatch(
    records,
    title: title,
    artist: artist,
    duration: duration,
    tolerance: tolerance,
  );

  group('selectBestMatch: duración', () {
    test('elige la duración más cercana dentro de la tolerancia', () {
      final best = select([
        record(203, label: 'lejos'),
        record(201, label: 'cerca'),
        record(198, label: 'medio'),
      ]);
      expect(picked(best), 'cerca');
    });

    test('compara con precisión de milisegundos', () {
      final best = select([
        record(218, label: '218'),
        record(219, label: '219'),
      ], duration: const Duration(milliseconds: 218700));
      expect(picked(best), '219');
    });

    test('descarta lo que queda fuera de la tolerancia', () {
      expect(select([record(204), record(150)]), isNull);
      expect(
        select([record(204)], tolerance: const Duration(seconds: 5)),
        isNotNull,
      );
    });

    test('el límite de la tolerancia es inclusivo', () {
      expect(select([record(203)]), isNotNull);
      expect(select([record(197)]), isNotNull);
    });

    test('a igual distancia conserva el primero de la lista', () {
      final best = select([
        record(201, label: 'primero'),
        record(199, label: 'segundo'),
        record(201, label: 'tercero'),
      ]);
      expect(picked(best), 'primero');
    });

    test('sin duración conocida acepta cualquier registro que coincida', () {
      final best = select([
        record(999, synced: false, plain: 'texto'),
        record(50, label: 'sincronizada'),
      ], duration: Duration.zero);
      expect(picked(best), 'sincronizada');
    });
  });

  group('selectBestMatch: tipo de letra', () {
    test('prefiere sincronizada aunque otra de solo texto esté más cerca', () {
      final best = select([
        record(200, synced: false, plain: 'solo texto'),
        record(202, label: 'sincronizada'),
      ]);
      expect(picked(best), 'sincronizada');
    });

    test('entre varias sincronizadas gana la más cercana', () {
      final best = select([
        record(200, synced: false, plain: 'texto exacto'),
        record(203, label: 'sincronizada lejos'),
        record(201, label: 'sincronizada cerca'),
      ]);
      expect(picked(best), 'sincronizada cerca');
    });

    test('a falta de sincronizada usa texto y, si no, instrumental', () {
      expect(
        select([
          record(200, instrumental: true),
          record(201, synced: false, plain: 'texto'),
        ])!.hasPlainLyrics,
        isTrue,
      );
      expect(select([record(200, instrumental: true)])!.instrumental, isTrue);
    });

    test('ignora registros sin letra ni marca de instrumental', () {
      expect(select([record(200, synced: false)]), isNull);
      expect(select(const []), isNull);
    });
  });

  group('selectBestMatch: título y artista', () {
    test('descarta otro título aunque la duración sea idéntica', () {
      final best = select([
        record(200, title: 'Otra canción', label: 'otra'),
        record(202, title: 'Tema', label: 'la buena'),
      ]);
      expect(picked(best), 'la buena');
      expect(select([record(200, title: 'Otra canción')]), isNull);
    });

    test('descarta otro artista aunque título y duración coincidan', () {
      final best = select([
        record(200, artist: 'Imitadores', label: 'versión'),
        record(202, artist: 'Grupo', label: 'original'),
      ]);
      expect(picked(best), 'original');
    });

    test('con artista desconocido vale cualquier artista', () {
      expect(
        select([record(200, artist: 'Quien sea')], artist: null),
        isNotNull,
      );
      expect(
        select([record(200, artist: 'Quien sea')], artist: '  '),
        isNotNull,
      );
    });

    test('ignora mayúsculas, acentos, signos y añadidos del título', () {
      for (final title in [
        'TEMA',
        'Téma',
        'Tema (feat. Otro)',
        'Tema [Official Video]',
        'Tema - Remastered 2011',
        'Grupo - Tema',
        '  tema!  ',
      ]) {
        expect(select([record(200, title: title)]), isNotNull, reason: title);
      }
    });

    test('exige palabras completas en el título', () {
      expect(select([record(200, title: 'Temario')]), isNull);
      expect(select([record(200, title: 'Sistema')]), isNull);
    });

    test('con varios artistas basta con que coincida uno', () {
      for (final artist in [
        'Grupo, Invitado',
        'Invitado & Grupo',
        'Grupo feat. Invitado',
        'Grupo ft Invitado',
        'Invitado x Grupo',
        'Grupo; Otro',
      ]) {
        expect(
          select([record(200)], artist: artist),
          isNotNull,
          reason: artist,
        );
      }
      expect(select([record(200)], artist: 'Invitado, Otro'), isNull);
    });

    test('acepta el artista escrito en el título del registro', () {
      // Quien lo subió puso su propio nombre como artista.
      expect(
        select([record(200, title: 'Grupo - Tema', artist: 'CanalDeVídeos')]),
        isNotNull,
      );
    });
  });

  group('normalizeForMatch', () {
    test('reduce el texto a palabras comparables', () {
      expect(normalizeForMatch("Don't Stop Me Now"), 'dont stop me now');
      expect(normalizeForMatch('Canción (En Vivo) [HD]'), 'cancion');
      expect(normalizeForMatch('Tema - Remastered 2011'), 'tema');
      expect(normalizeForMatch('AC/DC'), 'ac dc');
      expect(normalizeForMatch('  Beyoncé  '), 'beyonce');
    });

    test('no recorta guiones que forman parte del título', () {
      expect(normalizeForMatch('Anti-Hero'), 'anti hero');
      expect(normalizeForMatch('Grupo - Tema'), 'grupo tema');
    });
  });

  test('splitArtists separa las formas habituales', () {
    expect(splitArtists('A, B & C'), ['A', 'B', 'C']);
    expect(splitArtists('A feat. B'), ['A', 'B']);
    expect(splitArtists('A Featuring B'), ['A', 'B']);
    expect(splitArtists('Solo Uno'), ['Solo Uno']);
    // «x» y «con» solo separan como palabras sueltas.
    expect(splitArtists('Xavier Conrad'), ['Xavier Conrad']);
  });

  // Datos reales de LRCLIB para «Love Me Not» de Ravyn Lenae: la misma
  // canción tiene versiones de muchas duraciones y además registros con
  // duraciones disparatadas.
  group('caso real: Love Me Not', () {
    LrclibRecord real(
      num seconds, {
      String title = 'Love Me Not',
      String artist = 'Ravyn Lenae',
    }) => record(seconds, title: title, artist: artist);

    final results = [
      real(213),
      real(213),
      real(222),
      real(219),
      real(2976),
      real(2990),
      real(218),
      real(214, title: 'Ravyn Lenae - Love Me Not', artist: 'R&BHype'),
      real(181),
      real(188, title: 'Love Me Not (feat. Rex Orange County)'),
      real(197, title: 'love me not', artist: 'ravyn lenae'),
      real(221),
      real(218.664),
      real(82, artist: 'Edward Skeletrix'),
      real(160, artist: 'In Her Own Words'),
    ];

    String? forDuration(double seconds) => picked(
      select(
        results,
        title: 'Love Me Not',
        artist: 'Ravyn Lenae',
        duration: Duration(milliseconds: (seconds * 1000).round()),
      ),
    );

    test('cada duración de archivo obtiene su versión', () {
      expect(forDuration(213.2), '213');
      expect(forDuration(214.0), '214');
      expect(forDuration(218.7), '218.664');
      expect(forDuration(219.4), '219');
      expect(forDuration(220.6), '221');
      expect(forDuration(222.3), '222');
      expect(forDuration(188.4), '188');
      expect(forDuration(181.0), '181');
    });

    test('no confunde la canción con las de otros artistas', () {
      expect(forDuration(82.0), isNull);
      expect(forDuration(160.0), isNull);
    });

    test('una duración sin versión cercana no devuelve nada', () {
      expect(forDuration(205.0), isNull);
      expect(forDuration(300.0), isNull);
    });
  });

  // Tiempos tomados de dos registros reales de LRCLIB para la misma canción
  // de 213 s: uno sincronizado de verdad y otro con tiempos inventados.
  group('hasReliableSync', () {
    const good = '''
[00:16.88] See, right now, I need you
[00:21.10] You up now? I see you
[00:25.45] Slow down, be cool
[00:29.54] It's yours now, keep it
[00:33.75] I need you right now
[00:37.77] If I get you
[00:41.97] And, oh, it's hard to see you
[00:46.34] Oh, it's hard to leave you
[00:50.57] All this time
[03:17.97] Última línea
''';
    const machineMade = '''
[00:00.00] See, right now, I need you
[00:05.20] You up now, I see you
[00:10.40] Slow down, be cool
[00:15.60] It's yours now, keep it
[00:20.80] I need you right now
[00:26.20] If I get you
[00:33.00] And, oh, it's hard to see you
[00:38.80] Oh, it's hard to leave you
[00:44.00] All this time
[00:49.20] Otra línea
[00:54.40] Otra más
''';
    const song = Duration(milliseconds: 213499);

    LrclibRecord withSync(String synced, {num seconds = 213}) => LrclibRecord(
      trackName: 'Tema',
      artistName: 'Grupo',
      duration: Duration(milliseconds: (seconds * 1000).round()),
      syncedLyrics: synced,
      plainLyrics: 'See, right now, I need you\nYou up now',
    );

    test('acepta una sincronización hecha con el audio', () {
      expect(hasReliableSync(withSync(good), song), isTrue);
    });

    test('rechaza tiempos repartidos a intervalos idénticos', () {
      expect(hasReliableSync(withSync(machineMade), song), isFalse);
    });

    test('rechaza una letra que sigue después del final de la canción', () {
      const overrun = '[00:10.00]a\n[01:00.37]b\n[04:20.20]fuera';
      expect(hasReliableSync(withSync(overrun), song), isFalse);
      // La misma letra encaja en una canción más larga.
      expect(
        hasReliableSync(withSync(overrun), const Duration(minutes: 5)),
        isTrue,
      );
    });

    test('sin duración de la canción usa la del registro', () {
      const overrun = '[00:10.00]a\n[04:20.20]fuera';
      expect(hasReliableSync(withSync(overrun), Duration.zero), isFalse);
      expect(
        hasReliableSync(withSync(overrun, seconds: 300), Duration.zero),
        isTrue,
      );
    });

    test('no juzga los intervalos de letras muy cortas', () {
      const short = '[00:05.00]a\n[00:10.00]b\n[00:15.00]c\n[00:20.00]d';
      expect(hasReliableSync(withSync(short), song), isTrue);
    });

    test('un ritmo constante con variaciones de centésimas es fiable', () {
      const steady = '''
[00:10.00]a
[00:14.22]b
[00:18.57]c
[00:22.66]d
[00:26.87]e
[00:30.89]f
[00:35.09]g
[00:39.46]h
[00:43.69]i
[00:47.90]j
''';
      expect(hasReliableSync(withSync(steady), song), isTrue);
    });

    test('sin letra sincronizada no hay nada fiable', () {
      expect(
        hasReliableSync(record(213, synced: false, plain: 'x'), song),
        isFalse,
      );
    });

    test('la selección prefiere una fiable a una inventada más cercana', () {
      final best = selectBestMatch(
        [withSync(machineMade, seconds: 213.5), withSync(good, seconds: 214)],
        title: 'Tema',
        artist: 'Grupo',
        duration: song,
      );
      expect(best!.syncedLyrics, good);
    });

    test('si solo hay inventadas se muestra como texto, sin tiempos', () {
      final best = selectBestMatch(
        [withSync(machineMade)],
        title: 'Tema',
        artist: 'Grupo',
        duration: song,
      )!;
      final lyrics = best.toLyrics(songDuration: song)!;
      expect(lyrics.isSynced, isFalse);
      expect(lyrics.plainText, startsWith('See, right now, I need you'));
    });

    test('sin texto plano, el de la sincronizada no fiable sirve de texto', () {
      final lyrics = const LrclibRecord(
        trackName: 'Tema',
        artistName: 'Grupo',
        duration: Duration(seconds: 213),
        syncedLyrics: machineMade,
      ).toLyrics(songDuration: song)!;
      expect(lyrics.isSynced, isFalse);
      expect(lyrics.plainText, contains('Slow down, be cool'));
      expect(lyrics.plainText, isNot(contains('[00:')));
    });
  });

  group('LrclibRecord', () {
    test('lee nombres, duración con decimales y campos nulos', () {
      final parsed = LrclibRecord.fromJson(json(200.6));
      expect(parsed.trackName, 'Tema');
      expect(parsed.artistName, 'Grupo');
      expect(parsed.duration, const Duration(milliseconds: 200600));
      expect(parsed.isUseful, isFalse);
      expect(parsed.toLyrics(), isNull);
    });

    test('rechaza lo que no es un objeto', () {
      expect(() => LrclibRecord.fromJson('texto'), throwsFormatException);
      expect(() => LrclibRecord.fromJson(null), throwsFormatException);
    });

    test('toLyrics prefiere sincronizada, luego texto, luego instrumental', () {
      final both = record(1, plain: 'a').toLyrics()!;
      expect(both.isSynced, isTrue);
      expect(both.origin, LyricsOrigin.lrclib);
      expect(record(1, synced: false, plain: 'a').toLyrics()!.plainText, 'a');
      expect(record(1, instrumental: true).toLyrics()!.instrumental, isTrue);
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

    /// Servidor simulado: responde por ruta y por tipo de búsqueda.
    Future<http.Response> Function(http.Request) server({
      Object? get,
      List<Object> fields = const [],
      List<Object> text = const [],
      List<Uri>? log,
    }) => (request) async {
      log?.add(request.url);
      if (request.url.path == '/api/get') {
        return get == null ? http.Response('{}', 404) : ok(get);
      }
      return ok(request.url.queryParameters.containsKey('q') ? text : fields);
    };

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

    test('envía la duración redondeada, no truncada', () async {
      final log = <Uri>[];
      await client(server(log: log)).fetch(
        song(
          1,
          title: 'Tema',
          artist: 'Grupo',
          duration: const Duration(milliseconds: 218700),
        ),
      );
      expect(log.first.queryParameters['duration'], '219');
    });

    test(
      'una coincidencia directa casi exacta no hace más consultas',
      () async {
        final log = <Uri>[];
        final lyrics = await client(
          server(
            get: json(200.4, synced: '[00:01.00]exacta'),
            log: log,
          ),
        ).fetch(tema);
        expect(lyrics!.lines.single.text, 'exacta');
        expect(log.length, 1);
      },
    );

    test(
      'si la directa no es la más cercana, busca y elige la mejor',
      () async {
        // /api/get admite ±2 s y devuelve una versión cualquiera de las que
        // encajan; aquí hay otra más cercana en la búsqueda.
        final log = <Uri>[];
        final lyrics = await client(
          server(
            get: json(198, synced: '[00:01.00]directa a 2 s'),
            fields: [
              json(260, synced: '[00:01.00]versión en directo'),
              json(200, synced: '[00:01.00]la más cercana'),
            ],
            log: log,
          ),
        ).fetch(tema);
        expect(lyrics!.lines.single.text, 'la más cercana');
        expect(log.map((u) => u.path), ['/api/get', '/api/search']);
      },
    );

    test('si /api/get responde 404 busca por título y artista', () async {
      final log = <Uri>[];
      final lyrics = await client(
        server(
          fields: [json(200, synced: '[00:01.00]hallada')],
          log: log,
        ),
      ).fetch(tema);
      expect(log[1].queryParameters, {
        'track_name': 'Tema',
        'artist_name': 'Grupo',
      });
      expect(lyrics!.lines.single.text, 'hallada');
    });

    test('amplía con la búsqueda de texto si aún no hay una exacta', () async {
      final log = <Uri>[];
      final lyrics = await client(
        server(
          fields: [json(203, synced: '[00:01.00]a 3 s')],
          text: [json(200, synced: '[00:01.00]exacta en texto libre')],
          log: log,
        ),
      ).fetch(tema);
      expect(log.last.queryParameters, {'q': 'tema grupo'});
      expect(lyrics!.lines.single.text, 'exacta en texto libre');
    });

    test('junta los candidatos de todas las consultas', () async {
      final lyrics = await client(
        server(
          get: json(202, synced: '[00:01.00]directa'),
          fields: [json(203, synced: '[00:01.00]campos')],
          text: [json(198.5, synced: '[00:01.00]texto')],
        ),
      ).fetch(tema);
      // 198,5 s queda a 1,5 s; la directa (202) a 2 s.
      expect(lyrics!.lines.single.text, 'texto');
    });

    test('descarta resultados de otro título u otro artista', () async {
      final lyrics = await client(
        server(
          fields: [
            json(
              200,
              title: 'Tema parecido',
              artist: 'Otros',
              synced: '[00:01.00]no',
            ),
            json(200, title: 'Otra', synced: '[00:01.00]tampoco'),
          ],
          text: [json(201, synced: '[00:01.00]esta sí')],
        ),
      ).fetch(tema);
      expect(lyrics!.lines.single.text, 'esta sí');
    });

    test('devuelve null si nada coincide', () async {
      expect(await client(server()).fetch(tema), isNull);
      expect(
        await client(
          server(fields: [json(260, synced: '[00:01.00]otra versión')]),
        ).fetch(tema),
        isNull,
      );
      // Todas las rutas pueden responder 404.
      expect(
        await client((_) async => http.Response('', 404)).fetch(tema),
        isNull,
      );
    });

    test('reconoce las canciones instrumentales', () async {
      final lyrics = await client(server(get: json(200, instrumental: true)))
          .fetch(tema);
      expect(lyrics!.instrumental, isTrue);
    });

    test('con varios artistas busca por el principal', () async {
      final log = <Uri>[];
      await client(server(log: log)).fetch(
        song(
          1,
          title: 'Tema',
          artist: 'Grupo feat. Invitado',
          duration: target,
        ),
      );
      expect(log[0].queryParameters['artist_name'], 'Grupo feat. Invitado');
      expect(log[1].queryParameters['artist_name'], 'Grupo');
      expect(log[2].queryParameters['q'], 'tema grupo');
    });

    test('omite álbum y artista desconocidos y va directo a buscar', () async {
      final log = <Uri>[];
      await client(server(log: log)).fetch(
        song(1, title: 'Tema', artist: 'Grupo', album: Song.unknownAlbum),
      );
      expect(log.first.queryParameters.containsKey('album_name'), isFalse);

      log.clear();
      await client(server(log: log))
          .fetch(song(2, title: 'Tema', artist: Song.unknownArtist));
      expect(log.map((u) => u.path), ['/api/search', '/api/search']);
      expect(log.first.queryParameters, {'track_name': 'Tema'});
      expect(log.last.queryParameters, {'q': 'tema'});
    });

    test('si falla la búsqueda de texto conserva lo ya encontrado', () async {
      final lyrics = await client((request) async {
        if (request.url.path == '/api/get') return http.Response('{}', 404);
        if (request.url.queryParameters.containsKey('q')) {
          throw const SocketException('se cortó la red');
        }
        return ok([json(202, synced: '[00:01.00]de la primera búsqueda')]);
      }).fetch(tema);
      expect(lyrics!.lines.single.text, 'de la primera búsqueda');
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
