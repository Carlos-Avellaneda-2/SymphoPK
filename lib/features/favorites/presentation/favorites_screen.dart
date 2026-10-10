import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../library/presentation/library_screen.dart';
import '../../library/presentation/widgets/empty_state.dart';
import '../../library/presentation/widgets/screen_title.dart';
import 'favorites_providers.dart';

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songs = ref.watch(favoriteSongsProvider);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ScreenTitle(
              'Favoritos',
              subtitle: songs.isEmpty ? null : songCountLabel(songs.length),
            ),
            Expanded(
              child: songs.isEmpty
                  ? const EmptyState(
                      icon: Icons.favorite_border_rounded,
                      title: 'Aún no tienes favoritos',
                      message:
                          'Toca el corazón en el reproductor o en el menú '
                          'de una canción.',
                    )
                  : SongListView(songs: songs),
            ),
          ],
        ),
      ),
    );
  }
}
