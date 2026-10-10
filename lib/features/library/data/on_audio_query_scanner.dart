import 'dart:typed_data';

import 'package:on_audio_query_pluse/on_audio_query.dart';

import '../domain/song.dart';
import 'library_scanner.dart';

/// Implementación sobre MediaStore mediante `on_audio_query_pluse`.
class OnAudioQueryScanner implements LibraryScanner {
  OnAudioQueryScanner({OnAudioQuery? query}) : _query = query ?? OnAudioQuery();

  final OnAudioQuery _query;

  /// Descarta tonos, notificaciones y clips muy cortos.
  static const Duration _minDuration = Duration(seconds: 20);

  @override
  Future<List<Song>> scanSongs() async {
    final models = await _query.querySongs(
      sortType: SongSortType.TITLE,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );
    return [
      for (final model in models)
        if (_isMusic(model)) _toSong(model),
    ];
  }

  @override
  Future<Uint8List?> artwork(int songId, {int size = 600}) async {
    final bytes = await _query.queryArtwork(
      songId,
      ArtworkType.AUDIO,
      format: ArtworkFormat.JPEG,
      size: size,
      quality: 90,
    );
    return (bytes == null || bytes.isEmpty) ? null : bytes;
  }

  bool _isMusic(SongModel model) {
    if (model.isAlarm == true ||
        model.isNotification == true ||
        model.isRingtone == true) {
      return false;
    }
    return Duration(milliseconds: model.duration ?? 0) >= _minDuration;
  }

  Song _toSong(SongModel model) {
    final artist = model.artist;
    final album = model.album;
    return Song(
      id: model.id,
      title: model.title.isEmpty ? model.displayNameWOExt : model.title,
      artist: (artist == null || artist.isEmpty || artist == '<unknown>')
          ? 'Artista desconocido'
          : artist,
      album: (album == null || album.isEmpty) ? 'Álbum desconocido' : album,
      uri: model.uri ?? 'content://media/external/audio/media/${model.id}',
      duration: Duration(milliseconds: model.duration ?? 0),
      albumId: model.albumId,
      artistId: model.artistId,
      track: model.track,
      dateAdded: model.dateAdded,
    );
  }
}
