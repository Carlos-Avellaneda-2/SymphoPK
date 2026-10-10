import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:symphopk/features/player/domain/queue_manager.dart';
import 'package:symphopk/features/player/domain/queue_state.dart';

import '../support/songs.dart';

void main() {
  late QueueManager queue;

  List<int> ids() => queue.state.songs.map((s) => s.id).toList();

  setUp(() => queue = QueueManager(random: Random(42)));

  group('cola básica', () {
    test('empieza vacía', () {
      expect(queue.isEmpty, isTrue);
      expect(queue.current, isNull);
      expect(queue.state.index, -1);
      expect(queue.next(), isNull);
      expect(queue.previous(), isNull);
    });

    test('setQueue sitúa la reproducción en el índice pedido', () {
      queue.setQueue(songs(5), startIndex: 2);
      expect(queue.current!.id, 3);
      expect(ids(), [1, 2, 3, 4, 5]);
    });

    test('setQueue acota un índice fuera de rango', () {
      queue.setQueue(songs(3), startIndex: 99);
      expect(queue.current!.id, 3);
    });

    test('next y previous recorren la cola', () {
      queue.setQueue(songs(3));
      expect(queue.next()!.id, 2);
      expect(queue.next()!.id, 3);
      expect(queue.previous()!.id, 2);
    });

    test('jumpTo ignora índices inválidos', () {
      queue.setQueue(songs(3));
      expect(queue.jumpTo(7), isNull);
      expect(queue.current!.id, 1);
      expect(queue.jumpTo(2)!.id, 3);
    });

    test('add e insertNext', () {
      queue.setQueue(songs(3), startIndex: 1);
      queue.add(song(10));
      queue.insertNext(song(20));
      expect(ids(), [1, 2, 20, 3, 10]);
      expect(queue.current!.id, 2);
    });

    test('add sobre una cola vacía deja esa canción como actual', () {
      queue.add(song(7));
      expect(queue.current!.id, 7);
    });
  });

  group('repetir', () {
    test('sin repetir, la cola termina en la última canción', () {
      queue.setQueue(songs(2), startIndex: 1);
      expect(queue.next(auto: true), isNull);
      expect(queue.current!.id, 2, reason: 'no se mueve al terminar');
    });

    test('sin repetir, previous en la primera se queda en la primera', () {
      queue.setQueue(songs(3));
      expect(queue.previous()!.id, 1);
    });

    test('repetir todas vuelve al principio y al final', () {
      queue
        ..setQueue(songs(3), startIndex: 2)
        ..setRepeat(QueueRepeat.all);
      expect(queue.next(auto: true)!.id, 1);
      expect(queue.previous()!.id, 3);
    });

    test('repetir una mantiene la canción solo al terminar sola', () {
      queue
        ..setQueue(songs(3))
        ..setRepeat(QueueRepeat.one);
      expect(queue.next(auto: true)!.id, 1);
      expect(queue.next()!.id, 2, reason: 'el salto manual sí avanza');
    });

    test('repetir una: el salto manual en la última vuelve al inicio', () {
      queue
        ..setQueue(songs(2), startIndex: 1)
        ..setRepeat(QueueRepeat.one);
      expect(queue.next()!.id, 1);
    });
  });

  group('aleatorio', () {
    test('conserva la canción actual y la pone primera', () {
      queue.setQueue(songs(20), startIndex: 7);
      queue.setShuffle(true);
      expect(queue.state.shuffle, isTrue);
      expect(queue.state.index, 0);
      expect(queue.current!.id, 8);
    });

    test('baraja sin perder ni duplicar canciones', () {
      queue.setQueue(songs(20));
      queue.setShuffle(true);
      expect(ids().toSet(), {for (var i = 1; i <= 20; i++) i});
      expect(ids().length, 20);
      expect(ids(), isNot(orderedEquals([for (var i = 1; i <= 20; i++) i])));
    });

    test('al apagarlo recupera el orden original en la canción actual', () {
      queue.setQueue(songs(10));
      queue.setShuffle(true);
      queue.next();
      queue.next();
      final playing = queue.current!;
      queue.setShuffle(false);
      expect(ids(), [for (var i = 1; i <= 10; i++) i]);
      expect(queue.current, playing);
      expect(queue.state.index, playing.id - 1);
    });

    test('setQueue con aleatorio activo empieza por la canción elegida', () {
      queue.setShuffle(true);
      queue.setQueue(songs(10), startIndex: 4);
      expect(queue.current!.id, 5);
      expect(queue.state.index, 0);
      expect(queue.originalOrder.map((s) => s.id), [
        for (var i = 1; i <= 10; i++) i,
      ]);
    });

    test('recorre todas las canciones exactamente una vez', () {
      queue.setQueue(songs(8));
      queue.setShuffle(true);
      final played = <int>{queue.current!.id};
      while (queue.next(auto: true) != null) {
        played.add(queue.current!.id);
      }
      expect(played.length, 8);
    });

    test('insertNext con aleatorio respeta el orden original al apagarlo', () {
      queue.setQueue(songs(5), startIndex: 2);
      queue.setShuffle(true);
      queue.insertNext(song(99));
      expect(ids()[1], 99);
      queue.setShuffle(false);
      expect(ids(), [1, 2, 3, 99, 4, 5]);
    });
  });

  group('removeAt', () {
    test('quitar una anterior mantiene la canción actual', () {
      queue.setQueue(songs(4), startIndex: 2);
      expect(queue.removeAt(0), isFalse);
      expect(queue.current!.id, 3);
      expect(queue.state.index, 1);
    });

    test('quitar la actual pasa a la siguiente', () {
      queue.setQueue(songs(4), startIndex: 1);
      expect(queue.removeAt(1), isTrue);
      expect(queue.current!.id, 3);
    });

    test('quitar la actual siendo la última pasa a la anterior', () {
      queue.setQueue(songs(3), startIndex: 2);
      expect(queue.removeAt(2), isTrue);
      expect(queue.current!.id, 2);
    });

    test('quitar la única canción vacía la cola', () {
      queue.setQueue(songs(1));
      expect(queue.removeAt(0), isTrue);
      expect(queue.isEmpty, isTrue);
      expect(queue.current, isNull);
    });

    test('con aleatorio también la quita del orden original', () {
      queue.setQueue(songs(5));
      queue.setShuffle(true);
      final removed = queue.state.songs[3];
      queue.removeAt(3);
      queue.setShuffle(false);
      expect(ids(), isNot(contains(removed.id)));
      expect(ids().length, 4);
    });
  });

  group('move', () {
    test('mover la canción actual la sigue', () {
      queue.setQueue(songs(4), startIndex: 1);
      queue.move(1, 3);
      expect(ids(), [1, 3, 4, 2]);
      expect(queue.current!.id, 2);
    });

    test('mover otra canción por encima o por debajo ajusta el índice', () {
      queue.setQueue(songs(4), startIndex: 2);
      queue.move(0, 3);
      expect(queue.current!.id, 3);
      expect(queue.state.index, 1);
      queue.move(3, 0);
      expect(queue.current!.id, 3);
      expect(queue.state.index, 2);
    });
  });

  test('restore reproduce exactamente el estado guardado', () {
    final original = songs(4);
    final order = [original[2], original[0], original[3], original[1]];
    queue.restore(
      original: original,
      order: order,
      index: 1,
      shuffle: true,
      repeat: QueueRepeat.all,
    );
    expect(ids(), [3, 1, 4, 2]);
    expect(queue.current!.id, 1);
    expect(queue.state.repeat, QueueRepeat.all);
    queue.setShuffle(false);
    expect(ids(), [1, 2, 3, 4]);
  });
}
