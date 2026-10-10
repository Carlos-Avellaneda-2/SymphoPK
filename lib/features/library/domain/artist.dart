import 'package:flutter/foundation.dart';

import 'song.dart';

@immutable
class Artist {
  const Artist({
    required this.key,
    required this.name,
    required this.songs,
    required this.albumCount,
  });

  final String key;
  final String name;
  final List<Song> songs;
  final int albumCount;

  Song get cover => songs.first;
}
