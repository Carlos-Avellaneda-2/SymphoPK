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
import 'package:symphopk/features/favorites/presentation/favorites_providers.dart';
import 'package:symphopk/features/home/home_shell.dart';
import 'package:symphopk/features/library/data/library_scanner.dart';
import 'package:symphopk/features/library/domain/song.dart';
import 'package:symphopk/features/library/presentation/library_providers.dart';
import 'package:symphopk/features/player/data/sympho_audio_handler.dart';
import 'package:symphopk/features/player/domain/queue_state.dart';
import 'package:symphopk/features/player/presentation/player_providers.dart';
import 'package:symphopk/features/player/presentation/player_screen.dart';
import 'package:symphopk/features/playlists/domain/playlist.dart';
import 'package:symphopk/features/playlists/presentation/playlist_providers.dart';

class _MockHandler extends Mock implements SymphoAudioHandler {}

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

  setUpAll(() async {
    await _loadFonts();
  });

  setUp(() {
    handler = _MockHandler();
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
