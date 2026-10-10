import 'package:flutter/material.dart';

import '../library/presentation/library_screen.dart';
import '../player/presentation/widgets/mini_player.dart';

/// Estructura principal. El contenido vive en un `Navigator` anidado para
/// que los elementos fijos (mini reproductor, barra inferior) sigan visibles
/// al entrar en un álbum, un artista o una lista.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: const SafeArea(top: false, child: MiniPlayer()),
      body: NavigatorPopHandler<Object?>(
        // El botón atrás del sistema retrocede dentro del navegador anidado.
        onPopWithResult: (_) => _navigatorKey.currentState?.maybePop(),
        child: Navigator(
          key: _navigatorKey,
          onGenerateRoute: (settings) => MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => const LibraryScreen(),
          ),
        ),
      ),
    );
  }
}
