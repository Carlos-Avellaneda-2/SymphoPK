import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../favorites/presentation/favorites_screen.dart';
import '../library/presentation/library_screen.dart';
import '../player/presentation/player_providers.dart';
import '../player/presentation/widgets/mini_player.dart';
import '../playlists/presentation/playlists_screen.dart';
import '../settings/presentation/settings_screen.dart';

/// Estructura principal. El contenido vive en un `Navigator` anidado para
/// que el mini reproductor y la barra inferior sigan visibles al entrar en
/// un álbum, un artista o una lista.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _tab = ValueNotifier<int>(0);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  void _selectTab(int index) {
    // Cambiar de pestaña (o repetir la actual) vuelve a la raíz.
    _navigatorKey.currentState?.popUntil((route) => route.isFirst);
    _tab.value = index;
  }

  @override
  Widget build(BuildContext context) {
    // Mantiene viva la restauración y el guardado de la última sesión.
    ref.listen(playbackSessionProvider, (_, _) {});

    return Scaffold(
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          ValueListenableBuilder(
            valueListenable: _tab,
            builder: (context, index, _) => NavigationBar(
              selectedIndex: index,
              onDestinationSelected: _selectTab,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.library_music_outlined),
                  selectedIcon: Icon(Icons.library_music_rounded),
                  label: 'Biblioteca',
                ),
                NavigationDestination(
                  icon: Icon(Icons.favorite_border_rounded),
                  selectedIcon: Icon(Icons.favorite_rounded),
                  label: 'Favoritos',
                ),
                NavigationDestination(
                  icon: Icon(Icons.queue_music_outlined),
                  selectedIcon: Icon(Icons.queue_music_rounded),
                  label: 'Listas',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings_rounded),
                  label: 'Ajustes',
                ),
              ],
            ),
          ),
        ],
      ),
      body: NavigatorPopHandler<Object?>(
        // El botón atrás del sistema retrocede dentro del navegador anidado.
        onPopWithResult: (_) => _navigatorKey.currentState?.maybePop(),
        child: Navigator(
          key: _navigatorKey,
          onGenerateRoute: (settings) => MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => ValueListenableBuilder(
              valueListenable: _tab,
              // IndexedStack conserva el scroll y la búsqueda de cada pestaña.
              builder: (context, index, _) => IndexedStack(
                index: index,
                children: const [
                  LibraryScreen(),
                  FavoritesScreen(),
                  PlaylistsScreen(),
                  SettingsScreen(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
