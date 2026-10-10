import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library_providers.dart';

/// Carátula cuadrada de una canción con esquinas redondeadas y un marcador
/// cuando no hay imagen. [resolution] es el lado en píxeles que se pide a
/// MediaStore (no el tamaño en pantalla).
class ArtworkImage extends ConsumerStatefulWidget {
  const ArtworkImage({
    super.key,
    required this.songId,
    this.size,
    this.radius = 8,
    this.resolution = 200,
  });

  static const int thumbnail = 200;
  static const int full = 800;

  final int? songId;

  /// Lado en píxeles lógicos; `null` para ocupar el espacio disponible.
  final double? size;
  final double radius;
  final int resolution;

  @override
  ConsumerState<ArtworkImage> createState() => _ArtworkImageState();
}

class _ArtworkImageState extends ConsumerState<ArtworkImage> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ArtworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.songId != widget.songId ||
        oldWidget.resolution != widget.resolution) {
      _load();
    }
  }

  void _load() {
    final id = widget.songId;
    if (id == null) {
      _bytes = null;
      return;
    }
    final repository = ref.read(artworkRepositoryProvider);
    if (repository.isCached(id, widget.resolution)) {
      _bytes = repository.peek(id, widget.resolution);
      return;
    }
    // Mientras llega la versión grande se muestra la miniatura si ya existe.
    _bytes = repository.peek(id, ArtworkImage.thumbnail);
    final resolution = widget.resolution;
    repository.load(id, size: resolution).then((bytes) {
      if (!mounted || widget.songId != id || widget.resolution != resolution) {
        return;
      }
      setState(() => _bytes = bytes);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bytes = _bytes;
    final Widget content = bytes == null
        ? ColoredBox(
            color: scheme.surfaceContainerHighest,
            child: LayoutBuilder(
              builder: (context, constraints) => Icon(
                Icons.music_note_rounded,
                size: constraints.biggest.shortestSide * 0.45,
                color: scheme.onSurfaceVariant,
              ),
            ),
          )
        : Image.memory(
            bytes,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) =>
                ColoredBox(color: scheme.surfaceContainerHighest),
          );
    return SizedBox.square(
      dimension: widget.size,
      child: AspectRatio(
        aspectRatio: 1,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.radius),
          child: content,
        ),
      ),
    );
  }
}
