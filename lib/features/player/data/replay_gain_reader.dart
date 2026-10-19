import 'dart:io';
import 'dart:isolate';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

import '../domain/replay_gain.dart';

/// Lee los valores ReplayGain de un archivo de audio.
typedef ReplayGainReader = Future<ReplayGainInfo?> Function(String path);

/// Implementación con `audio_metadata_reader`, en un isolate aparte para no
/// bloquear la interfaz. Admite MP3 (ID3 `TXXX`), FLAC y Ogg (Vorbis
/// comments) y etiquetas APE. Los MP4/M4A no guardan ReplayGain en un
/// formato estándar y se reproducen sin normalizar.
Future<ReplayGainInfo?> readReplayGain(String path) {
  if (path.isEmpty) return Future.value();
  return Isolate.run(() {
    try {
      final tags = switch (readAllMetadata(File(path), getImage: false)) {
        final Mp3Metadata mp3 => mp3.customMetadata,
        final VorbisMetadata vorbis => {
          'replaygain_track_gain': ?vorbis.replayGainTrackGain.firstOrNull,
          'replaygain_track_peak': ?vorbis.replayGainTrackPeak.firstOrNull,
          'replaygain_album_gain': ?vorbis.replayGainAlbumGain.firstOrNull,
          'replaygain_album_peak': ?vorbis.replayGainAlbumPeak.firstOrNull,
        },
        final ApeMetadata ape => ape.unknowns,
        _ => const <String, String>{},
      };
      final info = ReplayGainInfo.fromTags(tags);
      return info.isEmpty ? null : info;
    } on Object {
      return null; // formato no soportado o archivo ilegible
    }
  });
}
