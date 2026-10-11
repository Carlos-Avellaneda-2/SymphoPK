import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../player/presentation/player_providers.dart';
import '../data/lyrics_repository.dart';
import '../domain/lyrics.dart';
import 'lyrics_providers.dart';

/// Panel de letras de la canción actual. Toma los colores del tema que lo
/// rodea (en el reproductor, los de la carátula).
class LyricsPanel extends ConsumerWidget {
  const LyricsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Con el panel a la vista se va preparando la letra de la siguiente.
    ref.watch(lyricsPrefetchProvider);

    final lyrics = ref.watch(currentLyricsProvider);
    final songId = ref.watch(currentSongProvider.select((s) => s?.id));
    void retry() => ref.invalidate(currentLyricsProvider);

    // Al cambiar de canción `value` conserva la letra anterior hasta que
    // llega la nueva: se muestra «cargando» para no enseñar la que no es.
    if (lyrics.isLoading) return const _Loading();

    return switch (lyrics.value) {
      null => const _Loading(),
      LyricsFound(:final lyrics) when lyrics.isSynced => _SyncedLyrics(
        // La clave reinicia el scroll al cambiar de canción.
        key: ValueKey(songId),
        lyrics: lyrics,
      ),
      LyricsFound(:final lyrics) => _PlainLyrics(
        key: ValueKey(songId),
        lyrics: lyrics,
      ),
      LyricsInstrumental() => const _Message(
        icon: Icons.piano_rounded,
        title: 'Instrumental',
        message: 'Esta canción no tiene letra.',
      ),
      LyricsNotFound() => const _Message(
        icon: Icons.lyrics_outlined,
        title: 'Letra no encontrada',
        message:
            'No hay un archivo .lrc junto a la canción, no trae letra '
            'incrustada y LRCLIB no la tiene.',
      ),
      LyricsOffline() => _Message(
        icon: Icons.wifi_off_rounded,
        title: 'Sin conexión',
        message: 'Conéctate a internet para buscar la letra.',
        onRetry: retry,
      ),
      LyricsUnavailable() => _Message(
        icon: Icons.cloud_off_rounded,
        title: 'No se pudo obtener la letra',
        message: 'El servicio de letras no respondió correctamente.',
        onRetry: retry,
      ),
    };
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox.square(
            dimension: 28,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 16),
          Text(
            'Buscando letra…',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: scheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Reintentar'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Difumina los bordes superior e inferior de la letra.
class _FadedEdges extends StatelessWidget {
  const _FadedEdges({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          Colors.black,
          Colors.black,
          Colors.transparent,
        ],
        stops: [0, 0.12, 0.88, 1],
      ).createShader(bounds),
      child: child,
    );
  }
}

/// Texto que indica de dónde salió la letra.
class _Origin extends StatelessWidget {
  const _Origin(this.origin);

  final LyricsOrigin origin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Text(
        'Fuente: ${origin.label}',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Letra sin marcas de tiempo: texto que se desplaza a mano.
class _PlainLyrics extends StatelessWidget {
  const _PlainLyrics({super.key, required this.lyrics});

  final Lyrics lyrics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _FadedEdges(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              lyrics.plainText ?? '',
              style: theme.textTheme.titleMedium?.copyWith(height: 1.6),
            ),
            _Origin(lyrics.origin),
          ],
        ),
      ),
    );
  }
}

/// Letra sincronizada: resalta la línea actual, la mantiene centrada y
/// permite saltar a cualquier línea tocándola.
class _SyncedLyrics extends ConsumerStatefulWidget {
  const _SyncedLyrics({super.key, required this.lyrics});

  final Lyrics lyrics;

  @override
  ConsumerState<_SyncedLyrics> createState() => _SyncedLyricsState();
}

class _SyncedLyricsState extends ConsumerState<_SyncedLyrics> {
  /// Tiempo sin seguir la canción después de que el usuario desplace.
  static const Duration _manualScrollPause = Duration(seconds: 4);

  final _scrollController = ScrollController();
  late final List<GlobalKey> _lineKeys = [
    for (var i = 0; i < widget.lyrics.lines.length; i++) GlobalKey(),
  ];
  Timer? _resumeTimer;
  bool _followPaused = false;

  @override
  void initState() {
    super.initState();
    // Al abrir el panel se coloca directamente en la línea que suena.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _centerOn(ref.read(currentLyricIndexProvider), jump: true);
    });
  }

  @override
  void dispose() {
    _resumeTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _centerOn(int index, {bool jump = false}) {
    if (index < 0 || index >= _lineKeys.length) return;
    final lineContext = _lineKeys[index].currentContext;
    if (lineContext == null) return;
    Scrollable.ensureVisible(
      lineContext,
      alignment: 0.5,
      duration: jump ? Duration.zero : const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }

  bool _onScroll(ScrollNotification notification) {
    // Solo los desplazamientos hechos con el dedo traen `dragDetails`; los
    // del seguimiento automático no, así que no se pausan a sí mismos.
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _resumeTimer?.cancel();
      _followPaused = true;
    } else if (notification is ScrollEndNotification && _followPaused) {
      _resumeTimer?.cancel();
      _resumeTimer = Timer(_manualScrollPause, () {
        if (!mounted) return;
        _followPaused = false;
        _centerOn(ref.read(currentLyricIndexProvider));
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final lines = widget.lyrics.lines;
    final current = ref.watch(currentLyricIndexProvider);

    ref.listen(currentLyricIndexProvider, (_, index) {
      if (!_followPaused) _centerOn(index);
    });

    return _FadedEdges(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Medio panel de margen arriba y abajo para que la primera y la
          // última línea también puedan quedar centradas.
          final edge = constraints.maxHeight / 2;
          return NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: EdgeInsets.symmetric(vertical: edge),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < lines.length; i++)
                    _LyricLineTile(
                      key: _lineKeys[i],
                      text: lines[i].text,
                      isCurrent: i == current,
                      isPast: i < current,
                      onTap: () {
                        // Tocar una línea vuelve a seguir la canción.
                        _resumeTimer?.cancel();
                        _followPaused = false;
                        ref.read(audioHandlerProvider).seek(lines[i].time);
                      },
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: DefaultTextStyle.merge(
                      style: TextStyle(color: scheme.onSurfaceVariant),
                      child: _Origin(widget.lyrics.origin),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LyricLineTile extends StatelessWidget {
  const _LyricLineTile({
    super.key,
    required this.text,
    required this.isCurrent,
    required this.isPast,
    required this.onTap,
  });

  final String text;
  final bool isCurrent;
  final bool isPast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = isCurrent
        ? scheme.onSurface
        : scheme.onSurface.withValues(alpha: isPast ? 0.38 : 0.55);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          style: theme.textTheme.titleLarge!.copyWith(
            // El tamaño no cambia entre líneas: así el texto no se
            // recoloca al avanzar y solo varían color y grosor.
            fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
            color: color,
            height: 1.3,
          ),
          // Las pausas instrumentales se marcan con puntos; un símbolo
          // musical no existe en todas las tipografías.
          child: Text(text.isEmpty ? '• • •' : text),
        ),
      ),
    );
  }
}
