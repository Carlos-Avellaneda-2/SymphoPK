import 'dart:math';

import '../../library/domain/song.dart';
import 'queue_state.dart';

/// Lógica de la cola de reproducción: orden, aleatorio y repetición.
///
/// Es Dart puro, sin plugins, para poder probarla de forma aislada. Mantiene
/// dos listas: el orden original y el orden de reproducción. Con el aleatorio
/// apagado ambas coinciden; al apagarlo se recupera el orden original.
class QueueManager {
  QueueManager({Random? random}) : _random = random ?? Random();

  final Random _random;

  List<Song> _original = [];
  List<Song> _order = [];
  int _index = -1;
  bool _shuffle = false;
  QueueRepeat _repeat = QueueRepeat.off;

  QueueState get state => QueueState(
    songs: List.unmodifiable(_order),
    index: _index,
    shuffle: _shuffle,
    repeat: _repeat,
  );

  Song? get current =>
      _index >= 0 && _index < _order.length ? _order[_index] : null;

  int get length => _order.length;
  bool get isEmpty => _order.isEmpty;
  bool get shuffle => _shuffle;
  QueueRepeat get repeat => _repeat;

  /// Orden original, independiente del aleatorio (para persistirlo).
  List<Song> get originalOrder => List.unmodifiable(_original);

  /// Sustituye la cola y sitúa la reproducción en [startIndex].
  void setQueue(List<Song> songs, {int startIndex = 0}) {
    _original = List.of(songs);
    if (songs.isEmpty) {
      _order = [];
      _index = -1;
      return;
    }
    final start = startIndex.clamp(0, songs.length - 1);
    if (_shuffle) {
      _order = _shuffledFrom(start);
      _index = 0;
    } else {
      _order = List.of(songs);
      _index = start;
    }
  }

  /// Restaura una cola guardada tal cual, sin volver a barajar.
  void restore({
    required List<Song> original,
    required List<Song> order,
    required int index,
    required bool shuffle,
    required QueueRepeat repeat,
  }) {
    _shuffle = shuffle;
    _repeat = repeat;
    _original = List.of(original);
    _order = List.of(order);
    _index = order.isEmpty ? -1 : index.clamp(0, order.length - 1);
  }

  void setShuffle(bool enabled) {
    if (enabled == _shuffle) return;
    _shuffle = enabled;
    final playing = current;
    if (playing == null) return;
    final originalIndex = _original.indexOf(playing);
    if (enabled) {
      // La canción actual queda primera para no interrumpir la reproducción.
      _order = _shuffledFrom(originalIndex);
      _index = 0;
    } else {
      _order = List.of(_original);
      _index = originalIndex;
    }
  }

  void setRepeat(QueueRepeat mode) => _repeat = mode;

  /// Avanza a la siguiente canción y la devuelve, o `null` si la cola acabó.
  ///
  /// [auto] indica que la canción terminó sola; solo en ese caso «repetir
  /// una» mantiene la misma canción. Un salto manual siempre avanza.
  Song? next({bool auto = false}) {
    if (_order.isEmpty) return null;
    if (auto && _repeat == QueueRepeat.one) return current;
    if (_index < _order.length - 1) {
      _index++;
      return current;
    }
    if (_repeat == QueueRepeat.off) return null;
    _index = 0;
    return current;
  }

  /// Canción que sonaría al terminar sola la actual, sin avanzar la cola.
  Song? peekNext() {
    final index = _index;
    final song = next(auto: true);
    _index = index;
    return song;
  }

  /// Retrocede una canción. En la primera vuelve a la última solo con
  /// «repetir todas»; si no, se queda en la primera.
  Song? previous() {
    if (_order.isEmpty) return null;
    if (_index > 0) {
      _index--;
    } else if (_repeat == QueueRepeat.all) {
      _index = _order.length - 1;
    }
    return current;
  }

  Song? jumpTo(int index) {
    if (index < 0 || index >= _order.length) return null;
    _index = index;
    return current;
  }

  /// Añade al final de la cola.
  void add(Song song) {
    _original.add(song);
    _order.add(song);
    if (_index < 0) _index = 0;
  }

  /// Inserta justo después de la canción actual.
  void insertNext(Song song) {
    final playing = current;
    if (playing == null) {
      add(song);
      return;
    }
    _original.insert(_original.indexOf(playing) + 1, song);
    _order.insert(_index + 1, song);
  }

  /// Quita la canción en [index]. Devuelve `true` si era la que sonaba; en
  /// ese caso [current] pasa a ser la siguiente (o la anterior si era la
  /// última).
  bool removeAt(int index) {
    if (index < 0 || index >= _order.length) return false;
    final song = _order.removeAt(index);
    if (_shuffle) {
      _original.remove(song);
    } else {
      _original.removeAt(index);
    }
    final wasCurrent = index == _index;
    if (index < _index) {
      _index--;
    } else if (_index >= _order.length) {
      _index = _order.length - 1;
    }
    return wasCurrent;
  }

  /// Mueve una canción de [from] a [to] (índice final) sin cambiar cuál suena.
  void move(int from, int to) {
    if (from < 0 || from >= _order.length || to < 0 || to >= _order.length) {
      return;
    }
    if (from == to) return;
    final song = _order.removeAt(from);
    _order.insert(to, song);
    if (!_shuffle) _original = List.of(_order);
    if (from == _index) {
      _index = to;
    } else if (from < _index && to >= _index) {
      _index--;
    } else if (from > _index && to <= _index) {
      _index++;
    }
  }

  List<Song> _shuffledFrom(int currentIndex) {
    final rest = List.of(_original)..removeAt(currentIndex);
    rest.shuffle(_random);
    return [_original[currentIndex], ...rest];
  }
}
