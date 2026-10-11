import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:symphopk/features/lyrics/data/local_lyrics_sources.dart';
import 'package:symphopk/features/lyrics/domain/lrc_parser.dart';
import 'package:symphopk/features/lyrics/domain/lyrics.dart';

import '../support/songs.dart';

Duration ms(int value) => Duration(milliseconds: value);

void main() {
  group('parseLrc', () {
    test('lee marcas con centésimas, milésimas, décimas y sin fracción', () {
      final parsed = parseLrc('''
[00:12.34]centésimas
[01:02.345]milésimas
[00:05.5]décimas
[02:00]sin fracción
''');
      expect(parsed.lines, [
        LyricLine(ms(5500), 'décimas'),
        LyricLine(ms(12340), 'centésimas'),
        LyricLine(ms(62345), 'milésimas'),
        LyricLine(ms(120000), 'sin fracción'),
      ]);
    });

    test('admite dos puntos como separador de la fracción', () {
      expect(parseLrc('[00:10:50]hola').lines.single.time, ms(10500));
    });

    test('repite la línea en cada una de sus marcas de tiempo', () {
      final parsed = parseLrc('''
[00:10.00][00:50.00][01:30.00]Estribillo
[00:20.00]Verso
''');
      expect(parsed.lines, [
        LyricLine(ms(10000), 'Estribillo'),
        LyricLine(ms(20000), 'Verso'),
        LyricLine(ms(50000), 'Estribillo'),
        LyricLine(ms(90000), 'Estribillo'),
      ]);
    });

    test('ordena las líneas aunque el archivo venga desordenado', () {
      final parsed = parseLrc('[00:30.00]b\n[00:10.00]a\n[00:20.00]c');
      expect(parsed.lines.map((l) => l.text), ['a', 'c', 'b']);
    });

    test('conserva el orden del archivo entre líneas con la misma marca', () {
      final parsed = parseLrc('[00:10.00]primera\n[00:10.00]segunda');
      expect(parsed.lines.map((l) => l.text), ['primera', 'segunda']);
    });

    test('un offset positivo adelanta la letra', () {
      final parsed = parseLrc('[offset:+500]\n[00:10.00]hola');
      expect(parsed.lines.single.time, ms(9500));
    });

    test('un offset negativo la retrasa y vale sin signo', () {
      expect(
        parseLrc('[offset:-1000]\n[00:10.00]a').lines.single.time,
        ms(11000),
      );
      expect(
        parseLrc('[offset: 250]\n[00:10.00]a').lines.single.time,
        ms(9750),
      );
      expect(parseLrc('[OFFSET:250]\n[00:10.00]a').lines.single.time, ms(9750));
    });

    test('el offset se aplica aunque aparezca al final del archivo', () {
      final parsed = parseLrc('[00:10.00]hola\n[offset:1000]');
      expect(parsed.lines.single.time, ms(9000));
    });

    test('el offset nunca produce tiempos negativos', () {
      final parsed = parseLrc('[offset:5000]\n[00:01.00]a\n[00:10.00]b');
      expect(parsed.lines.first.time, Duration.zero);
      expect(parsed.lines.last.time, ms(5000));
    });

    test('ignora un offset que no es un número', () {
      expect(
        parseLrc('[offset:abc]\n[00:10.00]a').lines.single.time,
        ms(10000),
      );
    });

    test('mantiene las líneas vacías con marca como pausas', () {
      final parsed = parseLrc('[00:10.00]canta\n[00:20.00]\n[00:30.00]sigue');
      expect(parsed.lines, [
        LyricLine(ms(10000), 'canta'),
        LyricLine(ms(20000), ''),
        LyricLine(ms(30000), 'sigue'),
      ]);
    });

    test('ignora líneas en blanco, finales de línea Windows y espacios', () {
      final parsed = parseLrc(
        '\r\n  [00:10.00]  hola  \r\n\r\n[00:20.00]adiós\r\n',
      );
      expect(parsed.lines.map((l) => l.text), ['hola', 'adiós']);
    });

    test('descarta las etiquetas de metadatos', () {
      final parsed = parseLrc('''
[ar:Artista]
[ti:Título]
[al:Álbum]
[by:alguien]
[length:03:20]
[#:comentario]
[00:10.00]letra
''');
      expect(parsed.lines.single.text, 'letra');
      expect(parsed.plainText, 'letra');
    });

    test('quita las marcas por palabra del LRC mejorado', () {
      final parsed = parseLrc('[00:10.00]<00:10.00>Hola <00:10.50>mundo');
      expect(parsed.lines.single.text, 'Hola mundo');
    });

    test('conserva corchetes que no son marcas de tiempo', () {
      final parsed = parseLrc('[00:10.00][Estribillo] canta');
      expect(parsed.lines.single.text, '[Estribillo] canta');
    });

    test('sin marcas devuelve solo texto, conservando estrofas', () {
      final parsed = parseLrc('\nPrimera línea\nSegunda\n\nOtra estrofa\n\n');
      expect(parsed.isSynced, isFalse);
      expect(parsed.plainText, 'Primera línea\nSegunda\n\nOtra estrofa');
    });

    test('un texto vacío no produce nada', () {
      expect(parseLrc('').lines, isEmpty);
      expect(parseLrc('  \n \n').plainText, '');
    });
  });

  group('lyricsFromText', () {
    test('devuelve letra sincronizada si hay marcas', () {
      final lyrics = lyricsFromText(
        '[00:01.00]a\n[00:02.00]b',
        LyricsOrigin.lrcFile,
      )!;
      expect(lyrics.isSynced, isTrue);
      expect(lyrics.origin, LyricsOrigin.lrcFile);
      expect(lyrics.plainText, isNull);
    });

    test('devuelve texto estático si no hay marcas', () {
      final lyrics = lyricsFromText('una\ndos', LyricsOrigin.embedded)!;
      expect(lyrics.isSynced, isFalse);
      expect(lyrics.plainText, 'una\ndos');
    });

    test('devuelve null sin contenido útil', () {
      expect(lyricsFromText(null, LyricsOrigin.lrclib), isNull);
      expect(lyricsFromText('   ', LyricsOrigin.lrclib), isNull);
      expect(
        lyricsFromText('[ar:Solo metadatos]', LyricsOrigin.lrclib),
        isNull,
      );
      // Marcas de tiempo sin ninguna palabra.
      expect(
        lyricsFromText('[00:01.00]\n[00:02.00]', LyricsOrigin.lrclib),
        isNull,
      );
    });
  });

  group('currentLineIndex', () {
    final lines = [
      LyricLine(ms(1000), 'a'),
      LyricLine(ms(5000), 'b'),
      LyricLine(ms(9000), 'c'),
    ];

    test('antes de la primera línea no hay ninguna activa', () {
      expect(currentLineIndex(lines, Duration.zero), -1);
      expect(currentLineIndex(lines, ms(999)), -1);
      expect(currentLineIndex(const [], ms(999)), -1);
    });

    test('devuelve la última línea cuya marca ya pasó', () {
      expect(currentLineIndex(lines, ms(1000)), 0);
      expect(currentLineIndex(lines, ms(4999)), 0);
      expect(currentLineIndex(lines, ms(5000)), 1);
      expect(currentLineIndex(lines, ms(8000)), 1);
      expect(currentLineIndex(lines, ms(600000)), 2);
    });
  });

  group('lrcPathFor', () {
    test('cambia la extensión por .lrc', () {
      expect(lrcPathFor('/Music/Rock/tema.mp3'), '/Music/Rock/tema.lrc');
      expect(
        lrcPathFor('/Music/a.b/01. tema.final.flac'),
        '/Music/a.b/01. tema.final.lrc',
      );
    });

    test('sin extensión la añade, sin confundir puntos de carpetas', () {
      expect(lrcPathFor('/Music/v1.2/tema'), '/Music/v1.2/tema.lrc');
      expect(lrcPathFor('/Music/.oculto'), '/Music/.oculto.lrc');
    });

    test('devuelve null sin ruta', () {
      expect(lrcPathFor(''), isNull);
    });
  });

  group('decodeLyricsBytes', () {
    test('UTF-8 con y sin BOM', () {
      final text = '[00:01.00]canción';
      expect(decodeLyricsBytes(Uint8List.fromList(utf8.encode(text))), text);
      expect(
        decodeLyricsBytes(
          Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(text)]),
        ),
        text,
      );
    });

    test('Latin-1 cuando no es UTF-8 válido', () {
      expect(
        decodeLyricsBytes(Uint8List.fromList(latin1.encode('canción'))),
        'canción',
      );
    });

    test('UTF-16 con BOM en ambos órdenes de bytes', () {
      const text = 'año';
      final little = [
        0xFF,
        0xFE,
        for (final c in text.codeUnits) ...[c & 0xFF, c >> 8],
      ];
      final big = [
        0xFE,
        0xFF,
        for (final c in text.codeUnits) ...[c >> 8, c & 0xFF],
      ];
      expect(decodeLyricsBytes(Uint8List.fromList(little)), text);
      expect(decodeLyricsBytes(Uint8List.fromList(big)), text);
    });
  });

  group('LrcFileLyricsSource', () {
    test('lee el .lrc que acompaña a la canción', () async {
      String? requested;
      final source = LrcFileLyricsSource((path) async {
        requested = path;
        return Uint8List.fromList(utf8.encode('[00:01.00]hola'));
      });
      final lyrics = await source.find(song(1, path: '/Music/tema.mp3'));
      expect(requested, '/Music/tema.lrc');
      expect(lyrics!.origin, LyricsOrigin.lrcFile);
      expect(lyrics.lines.single.text, 'hola');
    });

    test(
      'devuelve null si no hay archivo, está vacío o falla la lectura',
      () async {
        final missing = LrcFileLyricsSource((_) async => null);
        final empty = LrcFileLyricsSource((_) async => Uint8List(0));
        final failing = LrcFileLyricsSource(
          (_) async => throw Exception('E/S'),
        );
        final target = song(1, path: '/Music/tema.mp3');
        expect(await missing.find(target), isNull);
        expect(await empty.find(target), isNull);
        expect(await failing.find(target), isNull);
      },
    );

    test('no intenta leer si la canción no tiene ruta', () async {
      var calls = 0;
      final source = LrcFileLyricsSource((_) async {
        calls++;
        return null;
      });
      expect(await source.find(song(1)), isNull);
      expect(calls, 0);
    });
  });

  group('EmbeddedLyricsSource', () {
    test('usa la letra de los metadatos, sincronizada o no', () async {
      final synced = EmbeddedLyricsSource(
        reader: (_) async => '[00:02.00]incrustada',
      );
      final plain = EmbeddedLyricsSource(reader: (_) async => 'solo texto');
      final target = song(1, path: '/Music/tema.mp3');
      expect((await synced.find(target))!.isSynced, isTrue);
      final lyrics = (await plain.find(target))!;
      expect(lyrics.origin, LyricsOrigin.embedded);
      expect(lyrics.plainText, 'solo texto');
    });

    test('devuelve null sin letra, sin ruta o si el lector falla', () async {
      final none = EmbeddedLyricsSource(reader: (_) async => null);
      final failing = EmbeddedLyricsSource(
        reader: (_) async => throw Exception('x'),
      );
      expect(await none.find(song(1, path: '/a.mp3')), isNull);
      expect(await failing.find(song(1, path: '/a.mp3')), isNull);
      expect(await none.find(song(1)), isNull);
    });
  });
}
