import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../equalizer/presentation/equalizer_screen.dart';
import '../../favorites/presentation/favorite_button.dart';
import '../../library/presentation/widgets/artwork_image.dart';
import '../../library/presentation/widgets/quality_badge.dart';
import '../../lyrics/presentation/lyrics_panel.dart';
import 'player_providers.dart';
import 'widgets/mini_player.dart';
import 'widgets/player_controls.dart';
import 'widgets/queue_sheet.dart';

/// Abre el reproductor a pantalla completa sobre toda la app (navegador
/// raíz), con una transición vertical que acompaña al Hero de la carátula.
Future<void> openPlayerScreen(BuildContext context) {
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 380),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, _, _) => const PlayerScreen(),
      transitionsBuilder: (_, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.08),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    ),
  );
}

/// Reproductor a pantalla completa. Siempre es oscuro y toma sus colores de
/// la carátula de la canción actual.
class PlayerScreen extends ConsumerWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Si la cola se vacía con la pantalla abierta, no hay nada que mostrar.
    ref.listen(currentSongProvider, (_, next) {
      if (next == null && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });

    // Mientras se calcula la paleta de la nueva canción se conserva la
    // anterior, así el cambio de color es una transición y no un parpadeo.
    final scheme = ref.watch(playerColorSchemeProvider).value;
    final theme = scheme == null
        ? AppTheme.dark()
        : AppTheme.fromScheme(scheme);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: AnimatedTheme(
        data: theme,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOut,
        child: const _PlayerBody(),
      ),
    );
  }
}

class _PlayerBody extends ConsumerStatefulWidget {
  const _PlayerBody();

  @override
  ConsumerState<_PlayerBody> createState() => _PlayerBodyState();
}

class _PlayerBodyState extends ConsumerState<_PlayerBody> {
  /// Alterna entre la carátula y el panel de letras.
  bool _showLyrics = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final song = ref.watch(currentSongProvider);
    final playing = ref.watch(isPlayingProvider).value ?? false;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _BlurredBackdrop(songId: song?.id),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Cerrar',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                        iconSize: 32,
                      ),
                      Expanded(
                        child: Text(
                          song?.album ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: scheme.onSurfaceVariant,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Ecualizador',
                        onPressed: () => openEqualizerScreen(context),
                        icon: const Icon(Icons.graphic_eq_rounded),
                      ),
                      IconButton(
                        tooltip: 'Cola de reproducción',
                        onPressed: () => showQueueSheet(context),
                        icon: const Icon(Icons.queue_music_rounded),
                      ),
                    ],
                  ),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 280),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      child: _showLyrics
                          ? const Padding(
                              key: ValueKey('lyrics'),
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: LyricsPanel(),
                            )
                          : _Artwork(
                              key: const ValueKey('artwork'),
                              songId: song?.id,
                              playing: playing,
                            ),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          layoutBuilder: (current, previous) => Stack(
                            alignment: Alignment.centerLeft,
                            children: [...previous, ?current],
                          ),
                          child: Column(
                            key: ValueKey(song?.id),
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                song?.title ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                song?.artist ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              if (song != null &&
                                  song.quality.label != null) ...[
                                const SizedBox(height: 8),
                                QualityBadge(quality: song.quality),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: _showLyrics ? 'Ver carátula' : 'Ver letra',
                        isSelected: _showLyrics,
                        onPressed: () =>
                            setState(() => _showLyrics = !_showLyrics),
                        icon: const Icon(Icons.lyrics_outlined),
                        selectedIcon: Icon(
                          Icons.lyrics_rounded,
                          color: scheme.primary,
                        ),
                        iconSize: 28,
                      ),
                      FavoriteButton(songId: song?.id, size: 28),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const SeekBar(),
                  const SizedBox(height: 12),
                  const TransportControls(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Carátula grande con sombra; se encoge un poco en pausa.
class _Artwork extends StatelessWidget {
  const _Artwork({super.key, required this.songId, required this.playing});

  final int? songId;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: AnimatedScale(
          scale: playing ? 1 : 0.9,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          child: AspectRatio(
            aspectRatio: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 40,
                    spreadRadius: -4,
                    offset: const Offset(0, 20),
                  ),
                ],
              ),
              child: Hero(
                tag: artworkHeroTag,
                child: ArtworkImage(
                  songId: songId,
                  radius: 28,
                  resolution: ArtworkImage.full,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fondo: la propia carátula muy difuminada y oscurecida con un degradado
/// para que el texto mantenga contraste.
class _BlurredBackdrop extends StatelessWidget {
  const _BlurredBackdrop({required this.songId});

  final int? songId;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 600),
          child: SizedBox.expand(
            key: ValueKey(songId),
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: 48,
                sigmaY: 48,
                tileMode: TileMode.decal,
              ),
              child: FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: ArtworkImage(songId: songId, size: 200, radius: 0),
              ),
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                surface.withValues(alpha: 0.55),
                surface.withValues(alpha: 0.82),
                surface.withValues(alpha: 0.96),
              ],
              stops: const [0, 0.55, 1],
            ),
          ),
        ),
      ],
    );
  }
}
