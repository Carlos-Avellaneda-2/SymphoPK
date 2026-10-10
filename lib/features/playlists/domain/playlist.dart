import 'package:flutter/foundation.dart';

@immutable
class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    required this.songIds,
    required this.createdAt,
  });

  final int id;
  final String name;

  /// Ids de MediaStore en el orden de la lista.
  final List<int> songIds;
  final DateTime createdAt;
}
