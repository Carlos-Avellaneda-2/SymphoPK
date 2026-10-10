import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'favorites_providers.dart';

/// Corazón que marca o desmarca una canción como favorita.
class FavoriteButton extends ConsumerWidget {
  const FavoriteButton({super.key, required this.songId, this.size = 24});

  final int? songId;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = songId;
    final isFavorite =
        id != null &&
        ref.watch(favoriteIdSetProvider.select((ids) => ids.contains(id)));
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: isFavorite ? 'Quitar de favoritos' : 'Añadir a favoritos',
      onPressed: id == null
          ? null
          : () => ref.read(favoritesRepositoryProvider).toggle(id),
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutBack,
        transitionBuilder: (child, animation) =>
            ScaleTransition(scale: animation, child: child),
        child: Icon(
          isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          key: ValueKey(isFavorite),
          size: size,
          color: isFavorite ? scheme.primary : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
