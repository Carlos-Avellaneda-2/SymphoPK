// Pruebas de humo de las pantallas: se montan con datos falsos a tamaño de
// teléfono y fallan si algo desborda o lanza al construirse.
//
// Con la variable de entorno SCREENSHOT_DIR además guardan un PNG de cada
// pantalla, útil para revisar el diseño sin dispositivo:
//
//   SCREENSHOT_DIR=capturas flutter test test/ui
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:symphopk/core/permissions/permission_gate.dart';
import 'package:symphopk/core/theme/app_theme.dart';
import 'package:symphopk/features/equalizer/data/equalizer_controller.dart';
import 'package:symphopk/features/equalizer/data/equalizer_engine.dart';
import 'package:symphopk/features/equalizer/domain/equalizer_preset.dart';
import 'package:symphopk/features/equalizer/domain/equalizer_settings.dart';
import 'package:symphopk/features/equalizer/presentation/equalizer_providers.dart';
import 'package:symphopk/features/equalizer/presentation/equalizer_screen.dart';
import 'package:symphopk/features/favorites/presentation/favorites_providers.dart';
import 'package:symphopk/features/home/home_shell.dart';
import 'package:symphopk/features/library/data/library_scanner.dart';
import 'package:symphopk/features/library/domain/song.dart';
import 'package:symphopk/features/library/presentation/library_providers.dart';
import 'package:symphopk/core/database/database_provider.dart';
import 'package:symphopk/features/lyrics/data/lyrics_disk_cache.dart';
import 'package:symphopk/features/lyrics/data/lyrics_folder_access.dart';
import 'package:symphopk/features/lyrics/data/lyrics_repository.dart';
import 'package:symphopk/features/settings/data/app_preferences.dart';
import 'package:symphopk/features/settings/presentation/settings_screen.dart';
import 'package:symphopk/features/lyrics/domain/lyrics.dart';
import 'package:symphopk/features/lyrics/presentation/lyrics_providers.dart';
import 'package:symphopk/features/player/data/sympho_audio_handler.dart';
import 'package:symphopk/features/player/domain/queue_state.dart';
import 'package:symphopk/features/player/presentation/player_providers.dart';
import 'package:symphopk/features/player/presentation/player_screen.dart';
import 'package:symphopk/features/playlists/domain/playlist.dart';
import 'package:symphopk/features/playlists/presentation/playlist_providers.dart';

import '../support/memory_key_value_store.dart';

class _MockDiskCache extends Mock implements LyricsDiskCache {}

class _MockHandler extends Mock implements SymphoAudioHandler {}

class _MockEqualizer extends Mock implements EqualizerController {}

class _FakeScanner implements LibraryScanner {
  _FakeScanner(this._covers);

  final List<Uint8List> _covers;

  @override
  Future<Uint8List?> artwork(int songId, {int size = 600}) async =>
      songId % 4 == 0 ? null : _covers[songId % _covers.length];

  @override
  Future<List<Song>> scanSongs() async => _library;
}

final _library = [
  for (var i = 1; i <= 14; i++)
    Song(
      id: i,
      title: const [
        'Luz de invierno',
        'Un título bastante largo que no cabe en una sola línea',
        'Mareas',
        'Ciudad dormida',
        'Horizonte',
      ][i % 5],
      artist: const ['Aurora Vega', 'Los Nómadas', 'Delta Norte'][i % 3],
      album: const ['Cartografías', 'Noches de papel'][i % 2],
      uri: 'content://media/external/audio/media/$i',
      duration: Duration(seconds: 150 + i * 17),
      albumId: i % 2,
      artistId: i % 3,
      track: i,
      folder:
          '/storage/emulated/0/Music/${const ['Rock', 'Rock/Directos', 'Para estudiar'][i % 3]}',
    ),
];

/// Carátula sintética: un degradado diagonal entre dos colores.
Future<Uint8List> _cover(Color a, Color b) async {
  final recorder = ui.PictureRecorder();
  const rect = Rect.fromLTWH(0, 0, 64, 64);
  Canvas(recorder).drawRect(
    rect,
    Paint()
      ..shader = ui.Gradient.linear(rect.topLeft, rect.bottomRight, [a, b]),
  );
  final image = await recorder.endRecording().toImage(64, 64);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

/// Registra fuentes reales para que las capturas muestren texto e iconos en
/// lugar de los rectángulos de la fuente de test.
Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final dir = '$root/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, String file) async {
    final font = File('$dir/$file');
    if (!font.existsSync()) return;
    final bytes = await font.readAsBytes();
    await (FontLoader(
      family,
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  }

  await load('MaterialIcons', 'materialicons-regular.otf');
  // google_fonts nombra cada peso como una familia distinta.
  await load('Manrope_regular', 'roboto-regular.ttf');
  await load('Manrope_500', 'roboto-medium.ttf');
  await load('Manrope_600', 'roboto-medium.ttf');
  await load('Manrope_700', 'roboto-bold.ttf');
  await load('Manrope_800', 'roboto-black.ttf');
}

void main() {
  final shotKey = GlobalKey();
  late List<Uint8List> covers;
  late _MockHandler handler;
  late MemoryKeyValueStore store;
  late _MockDiskCache diskCache;

  setUpAll(() async {
    registerFallbackValue(Duration.zero);
    await _loadFonts();
  });

  setUp(() {
    handler = _MockHandler();
    store = MemoryKeyValueStore();
    diskCache = _MockDiskCache();
    when(() => diskCache.clear()).thenAnswer((_) async {});
    when(() => handler.skipToNext()).thenAnswer((_) async {});
    when(() => handler.skipToPrevious()).thenAnswer((_) async {});
    when(() => handler.play()).thenAnswer((_) async {});
    when(() => handler.pause()).thenAnswer((_) async {});
  });

  final queue = QueueState(
    songs: _library,
    index: 1,
    shuffle: true,
    repeat: QueueRepeat.all,
  );

  Future<void> pumpApp(
    WidgetTester tester,
    Widget home, {
    required Brightness brightness,
    QueueState? playing,
    List<Playlist> playlists = const [],
    LyricsResult? lyrics,
    EqualizerState equalizer = const EqualizerState(
      settings: EqualizerSettings(),
    ),
    AppPreferences preferences = const AppPreferences(),
    int lyricsCacheBytes = 0,
    List<LyricsFolder> lyricsFolders = const [],
  }) async {
    tester.view
      ..physicalSize = const Size(1080, 2340)
      ..devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    covers = (await tester.runAsync(
      () => Future.wait([
        _cover(const Color(0xFFFF7A59), const Color(0xFF5B2A86)),
        _cover(const Color(0xFF2EC4B6), const Color(0xFF14213D)),
        _cover(const Color(0xFFFFD166), const Color(0xFFEF476F)),
      ]),
    ))!;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioHandlerProvider.overrideWithValue(handler),
          libraryScannerProvider.overrideWithValue(_FakeScanner(covers)),
          queueStateProvider.overrideWith(
            (ref) => Stream.value(playing ?? const QueueState.empty()),
          ),
          isPlayingProvider.overrideWith((ref) => Stream.value(true)),
          positionProvider.overrideWith(
            (ref) => Stream.value(const Duration(seconds: 73)),
          ),
          playbackSessionProvider.overrideWith((ref) async {}),
          playerColorSchemeProvider.overrideWith(
            (ref) async => ColorScheme.fromSeed(
              seedColor: const Color(0xFFFF7A59),
              brightness: Brightness.dark,
            ),
          ),
          playlistsProvider.overrideWith((ref) => Stream.value(playlists)),
          playlistProvider.overrideWith(
            (ref, id) =>
                Stream.value(playlists.where((p) => p.id == id).firstOrNull),
          ),
          favoriteIdsProvider.overrideWith((ref) => Stream.value([3, 5])),
          equalizerControllerProvider.overrideWithValue(_MockEqualizer()),
          equalizerStateProvider.overrideWith((ref) => Stream.value(equalizer)),
          currentLyricsProvider.overrideWith((ref) async => lyrics),
          keyValueStoreProvider.overrideWithValue(store),
          initialPreferencesProvider.overrideWithValue(preferences),
          lyricsCacheSizeProvider.overrideWith((ref) async => lyricsCacheBytes),
          lyricsFoldersProvider.overrideWith((ref) async => lyricsFolders),
          lyricsDiskCacheProvider.overrideWithValue(diskCache),
        ],
        child: RepaintBoundary(
          key: shotKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: brightness == Brightness.dark
                ? ThemeMode.dark
                : ThemeMode.light,
            home: home,
          ),
        ),
      ),
    );
    await settle(tester);
  }

  screenTest('biblioteca con mini reproductor (oscuro)', (tester) async {
    await pumpApp(
      tester,
      const HomeShell(),
      brightness: Brightness.dark,
      playing: queue,
    );
    expect(find.text('Biblioteca'), findsWidgets);
    expect(find.byType(NavigationBar), findsOneWidget);
    await shot(tester, shotKey, '01_biblioteca_oscuro');

    await tester.tap(find.text('Carpetas'));
    await settle(tester);
    expect(find.text('Para estudiar'), findsOneWidget);
    await shot(tester, shotKey, '10_carpetas_oscuro');

    // Navegación anidada: Rock contiene la subcarpeta Directos.
    await tester.tap(find.text('Rock'));
    await settle(tester);
    expect(find.text('Directos'), findsOneWidget);
    expect(find.text('Music/Rock'), findsOneWidget);
    await shot(tester, shotKey, '11_carpeta_rock');
    await tester.pageBack();
    await settle(tester);

    await tester.tap(find.text('Álbumes'));
    await settle(tester);
    await shot(tester, shotKey, '02_albumes_oscuro');

    await tester.tap(find.text('Artistas'));
    await settle(tester);
    await shot(tester, shotKey, '03_artistas_oscuro');
  });

  screenTest('biblioteca en tema claro', (tester) async {
    await pumpApp(
      tester,
      const HomeShell(),
      brightness: Brightness.light,
      playing: queue,
    );
    await shot(tester, shotKey, '04_biblioteca_claro');
  });

  screenTest('reproductor a pantalla completa', (tester) async {
    await pumpApp(
      tester,
      const PlayerScreen(),
      brightness: Brightness.dark,
      playing: queue,
    );
    expect(find.text(_library[1].title), findsOneWidget);
    await shot(tester, shotKey, '05_reproductor');
  });

  screenTest('favoritos y listas', (tester) async {
    await pumpApp(
      tester,
      const HomeShell(),
      brightness: Brightness.dark,
      playlists: [
        Playlist(
          id: 1,
          name: 'Para correr',
          songIds: const [1, 2, 3],
          createdAt: DateTime(2026),
        ),
        Playlist(
          id: 2,
          name: 'Domingo',
          songIds: const [],
          createdAt: DateTime(2026),
        ),
      ],
    );
    await tester.tap(find.text('Favoritos'));
    await settle(tester);
    expect(find.text('2 canciones'), findsOneWidget);
    await shot(tester, shotKey, '06_favoritos');

    await tester.tap(find.text('Listas').last);
    await settle(tester);
    expect(find.text('Para correr'), findsOneWidget);
    await shot(tester, shotKey, '07_listas');

    await tester.tap(find.text('Para correr'));
    await settle(tester);
    expect(find.text('Reproducir'), findsOneWidget);
    await shot(tester, shotKey, '08_detalle_lista');
  });

  screenTest('ecualizador', (tester) async {
    const state = EqualizerState(
      settings: EqualizerSettings(
        enabled: true,
        preset: EqualizerPreset.rock,
        loudnessDb: 3,
      ),
      capabilities: EqualizerCapabilities(
        centerFrequencies: [60, 230, 910, 3600, 14000],
        minDb: -15,
        maxDb: 15,
      ),
      gains: [5, 3, -1, 3, 5],
    );
    await pumpApp(
      tester,
      const EqualizerScreen(),
      brightness: Brightness.dark,
      equalizer: state,
    );
    expect(find.text('Rock'), findsOneWidget);
    expect(find.text('Personalizado'), findsOneWidget);
    expect(find.text('3.6 kHz'), findsOneWidget);
    expect(find.text('+5 dB'), findsNWidgets(2));
    await shot(tester, shotKey, '12_ecualizador');
  });

  group('letras en el reproductor', () {
    final lyrics = Lyrics(
      origin: LyricsOrigin.lrclib,
      lines: [
        for (var i = 0; i < 24; i++)
          LyricLine(
            Duration(seconds: i * 10),
            i == 5 ? '' : 'Línea número $i de la canción',
          ),
      ],
    );

    Future<void> openLyrics(WidgetTester tester, LyricsResult result) async {
      await pumpApp(
        tester,
        const PlayerScreen(),
        brightness: Brightness.dark,
        playing: queue,
        lyrics: result,
      );
      await tester.tap(find.byTooltip('Ver letra'));
      await settle(tester);
    }

    screenTest('resalta la línea actual y salta al tocar otra', (tester) async {
      when(() => handler.seek(any())).thenAnswer((_) async {});
      await openLyrics(tester, LyricsFound(lyrics));

      // La posición simulada es 1:13, dentro de la línea 7 (1:10–1:20).
      final current = tester.widget<AnimatedDefaultTextStyle>(
        find
            .ancestor(
              of: find.text('Línea número 7 de la canción'),
              matching: find.byType(AnimatedDefaultTextStyle),
              // El más cercano es el de la línea; más arriba hay otros de Material.
            )
            .first,
      );
      expect(current.style.fontWeight, FontWeight.w800);
      expect(find.text('• • •'), findsOneWidget, reason: 'pausa instrumental');
      await shot(tester, shotKey, '13_letra_sincronizada');

      await tester.tap(find.text('Línea número 9 de la canción'));
      verify(() => handler.seek(const Duration(seconds: 90))).called(1);

      // Se puede volver a la carátula.
      await tester.tap(find.byTooltip('Ver carátula'));
      await settle(tester);
      expect(find.text('Línea número 7 de la canción'), findsNothing);
    });

    screenTest('muestra la letra sin sincronizar como texto', (tester) async {
      await openLyrics(
        tester,
        const LyricsFound(
          Lyrics(
            origin: LyricsOrigin.embedded,
            plainText: 'Primera estrofa\nsin marcas de tiempo',
          ),
        ),
      );
      expect(find.textContaining('Primera estrofa'), findsOneWidget);
      expect(find.text('Fuente: Incrustada en el archivo'), findsOneWidget);
    });

    screenTest('estados sin letra', (tester) async {
      await openLyrics(tester, const LyricsOffline());
      expect(find.text('Sin conexión'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      await shot(tester, shotKey, '14_letra_sin_conexion');
    });

    screenTest('instrumental y no encontrada no ofrecen reintentar', (
      tester,
    ) async {
      await openLyrics(tester, const LyricsInstrumental());
      expect(find.text('Instrumental'), findsOneWidget);
      expect(find.text('Reintentar'), findsNothing);
    });

    screenTest('letra no encontrada', (tester) async {
      await openLyrics(tester, const LyricsNotFound());
      expect(find.text('Letra no encontrada'), findsOneWidget);
    });

    screenTest('fallo del servicio permite reintentar', (tester) async {
      await openLyrics(tester, const LyricsUnavailable());
      expect(find.text('No se pudo obtener la letra'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
    });
  });

  group('ajustes', () {
    Future<void> openSettings(
      WidgetTester tester, {
      Brightness brightness = Brightness.dark,
      int lyricsCacheBytes = 0,
      List<LyricsFolder> lyricsFolders = const [],
    }) async {
      await pumpApp(
        tester,
        const HomeShell(),
        brightness: brightness,
        lyricsCacheBytes: lyricsCacheBytes,
        lyricsFolders: lyricsFolders,
        equalizer: const EqualizerState(
          settings: EqualizerSettings(
            enabled: true,
            preset: EqualizerPreset.jazz,
          ),
        ),
      );
      await tester.tap(find.text('Ajustes').last);
      await settle(tester);
    }

    screenTest('muestra las secciones y el estado actual', (tester) async {
      await openSettings(
        tester,
        lyricsCacheBytes: 3 * 1024 * 1024 ~/ 2,
        lyricsFolders: const [
          LyricsFolder(uri: 'tree', path: '/storage/emulated/0/Music'),
        ],
      );
      expect(find.text('Sistema'), findsOneWidget);
      expect(find.text('Activado · Jazz'), findsOneWidget);
      expect(find.text('1.5 MB en uso'), findsOneWidget);
      expect(find.text('Music'), findsOneWidget);
      await shot(tester, shotKey, '15_ajustes');
    });

    screenTest('elegir un tema lo guarda', (tester) async {
      await openSettings(tester);
      await tester.tap(find.text('Claro'));
      await settle(tester);
      expect(store.values[AppPreferences.themeModeKey], 'light');
      await tester.tap(find.text('Oscuro'));
      await settle(tester);
      expect(store.values[AppPreferences.themeModeKey], 'dark');
    });

    screenTest('«No guardar letras» se guarda', (tester) async {
      await openSettings(tester);
      await tester.tap(find.text('No guardar letras'));
      await settle(tester);
      expect(store.values[AppPreferences.saveLyricsKey], 'false');
    });

    screenTest('con la caché vacía no se puede borrar', (tester) async {
      await openSettings(tester);
      expect(find.text('Vacía'), findsOneWidget);
      final tile = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'Borrar caché de letras'),
      );
      expect(tile.enabled, isFalse);
    });
  });

  screenTest('permiso negado', (tester) async {
    await pumpApp(
      tester,
      PermissionDeniedView(
        permanentlyDenied: true,
        onRequest: () {},
        onOpenSettings: () {},
      ),
      brightness: Brightness.dark,
    );
    await shot(tester, shotKey, '09_permiso_negado');
  });
}

/// Como `testWidgets`, pero pintando sombras reales: por defecto los tests
/// las dibujan como bordes sólidos y las capturas no serían fieles. El valor
/// se restaura antes de que el framework verifique sus invariantes.
void screenTest(String description, Future<void> Function(WidgetTester) body) {
  testWidgets(description, (tester) async {
    debugDisableShadows = false;
    try {
      await body(tester);
    } finally {
      debugDisableShadows = true;
    }
  });
}

/// Deja que terminen futuros reales (decodificación de imágenes, streams) y
/// las animaciones.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Future<void> shot(WidgetTester tester, GlobalKey key, String name) async {
  final dir = Platform.environment['SCREENSHOT_DIR'];
  if (dir == null || dir.isEmpty) return;
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$dir/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
  });
}
