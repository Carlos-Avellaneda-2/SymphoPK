import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rxdart/rxdart.dart';
import 'package:symphopk/features/player/data/player_widget_sync.dart';
import 'package:symphopk/features/player/data/sympho_audio_handler.dart';
import 'package:symphopk/features/player/domain/queue_state.dart';

import '../support/songs.dart';

class _MockHandler extends Mock implements SymphoAudioHandler {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(PlayerWidgetSync.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late _MockHandler handler;
  late BehaviorSubject<QueueState> queue;
  late BehaviorSubject<PlaybackState> playback;
  late List<Map<Object?, Object?>> updates;
  late PlayerWidgetSync sync;

  QueueState queueOf(int index) => QueueState(
    songs: songs(3),
    index: index,
    shuffle: false,
    repeat: QueueRepeat.off,
  );

  /// Simula un toque en un botón del widget (mensaje nativo -> Dart).
  Future<void> sendFromWidget(String method) async {
    await messenger.handlePlatformMessage(
      PlayerWidgetSync.channelName,
      const StandardMethodCodec().encodeMethodCall(MethodCall(method)),
      (_) {},
    );
  }

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 200));

  setUp(() {
    handler = _MockHandler();
    queue = BehaviorSubject.seeded(const QueueState.empty());
    playback = BehaviorSubject.seeded(PlaybackState());
    updates = [];
    when(() => handler.queueState).thenAnswer((_) => queue);
    when(() => handler.playbackState).thenAnswer((_) => playback);
    when(() => handler.play()).thenAnswer((_) async {});
    when(() => handler.pause()).thenAnswer((_) async {});
    when(() => handler.skipToNext()).thenAnswer((_) async {});
    when(() => handler.skipToPrevious()).thenAnswer((_) async {});
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'update') {
        updates.add(call.arguments as Map<Object?, Object?>);
      }
      return null;
    });
    sync = PlayerWidgetSync(handler)..start();
  });

  tearDown(() async {
    await sync.dispose();
    messenger.setMockMethodCallHandler(channel, null);
    await queue.close();
    await playback.close();
  });

  test('sin cola envía un estado vacío y en pausa', () async {
    await settle();
    expect(updates.single, {
      'songId': null,
      'title': null,
      'artist': null,
      'playing': false,
    });
  });

  test('envía la canción y el estado cuando cambian', () async {
    queue.add(queueOf(1));
    playback.add(PlaybackState(playing: true));
    await settle();
    expect(updates.last, {
      'songId': 2,
      'title': 'Canción 2',
      'artist': 'Artista',
      'playing': true,
    });

    playback.add(PlaybackState(playing: false));
    await settle();
    expect(updates.last['playing'], false);
    expect(updates.last['songId'], 2);
  });

  test('no reenvía si cambia algo irrelevante para el widget', () async {
    queue.add(queueOf(0));
    await settle();
    final count = updates.length;
    // Misma canción y mismo estado: solo avanza la posición.
    playback.add(PlaybackState(updatePosition: const Duration(seconds: 9)));
    await settle();
    expect(updates.length, count);
  });

  test('toggle pausa si está sonando y reproduce si no', () async {
    playback.add(PlaybackState(playing: true));
    await sendFromWidget('toggle');
    verify(() => handler.pause()).called(1);

    playback.add(PlaybackState(playing: false));
    await sendFromWidget('toggle');
    verify(() => handler.play()).called(1);
  });

  test('next y previous saltan de canción', () async {
    await sendFromWidget('next');
    await sendFromWidget('previous');
    verify(() => handler.skipToNext()).called(1);
    verify(() => handler.skipToPrevious()).called(1);
  });

  test('requestState reenvía el estado actual', () async {
    queue.add(queueOf(2));
    await settle();
    updates.clear();
    await sendFromWidget('requestState');
    expect(updates.single['songId'], 3);
  });

  test('ignora la falta del lado nativo', () async {
    messenger.setMockMethodCallHandler(channel, null);
    queue.add(queueOf(0));
    await settle(); // no debe lanzar
  });
}
