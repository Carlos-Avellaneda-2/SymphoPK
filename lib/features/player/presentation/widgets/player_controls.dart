import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/formatters.dart';
import '../../domain/queue_state.dart';
import '../player_providers.dart';

/// Botón de reproducir/pausar con transición entre iconos.
class PlayPauseButton extends ConsumerWidget {
  const PlayPauseButton({super.key, this.size = 28, this.filled = false});

  final double size;

  /// Versión destacada con fondo circular (pantalla completa).
  final bool filled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = ref.watch(isPlayingProvider).value ?? false;
    final handler = ref.read(audioHandlerProvider);
    final scheme = Theme.of(context).colorScheme;
    final icon = AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      transitionBuilder: (child, animation) => ScaleTransition(
        scale: animation,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: Icon(
        playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
        key: ValueKey(playing),
        size: size,
      ),
    );
    void onPressed() => playing ? handler.pause() : handler.play();
    final tooltip = playing ? 'Pausar' : 'Reproducir';
    if (!filled) {
      return IconButton(onPressed: onPressed, tooltip: tooltip, icon: icon);
    }
    return IconButton.filled(
      onPressed: onPressed,
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        fixedSize: Size.square(size + 36),
      ),
      icon: icon,
    );
  }
}

/// Barra de progreso con arrastre y tiempos transcurrido / total.
class SeekBar extends ConsumerStatefulWidget {
  const SeekBar({super.key});

  @override
  ConsumerState<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends ConsumerState<SeekBar> {
  /// Valor mientras el usuario arrastra; evita saltos por el stream.
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final duration = ref.watch(currentSongProvider)?.duration ?? Duration.zero;
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final max = duration.inMilliseconds.toDouble();
    final value = (_dragValue ?? position.inMilliseconds.toDouble()).clamp(
      0.0,
      max <= 0 ? 0.0 : max,
    );
    final labelStyle = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            max: max <= 0 ? 1 : max,
            value: value,
            onChanged: max <= 0 ? null : (v) => setState(() => _dragValue = v),
            onChangeEnd: (v) async {
              await ref
                  .read(audioHandlerProvider)
                  .seek(Duration(milliseconds: v.round()));
              if (mounted) setState(() => _dragValue = null);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formatDuration(Duration(milliseconds: value.round())),
                style: labelStyle,
              ),
              Text(formatDuration(duration), style: labelStyle),
            ],
          ),
        ),
      ],
    );
  }
}

/// Fila de controles: aleatorio, anterior, play/pausa, siguiente, repetir.
class TransportControls extends ConsumerWidget {
  const TransportControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final queue = ref.watch(queueStateProvider).value;
    final shuffle = queue?.shuffle ?? false;
    final repeat = queue?.repeat ?? QueueRepeat.off;
    final handler = ref.read(audioHandlerProvider);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          tooltip: shuffle ? 'Desactivar aleatorio' : 'Activar aleatorio',
          isSelected: shuffle,
          color: shuffle ? scheme.primary : scheme.onSurfaceVariant,
          onPressed: () => handler.setShuffle(!shuffle),
          icon: const Icon(Icons.shuffle_rounded),
        ),
        IconButton(
          tooltip: 'Anterior',
          iconSize: 40,
          onPressed: handler.skipToPrevious,
          icon: const Icon(Icons.skip_previous_rounded),
        ),
        const PlayPauseButton(size: 40, filled: true),
        IconButton(
          tooltip: 'Siguiente',
          iconSize: 40,
          onPressed: handler.skipToNext,
          icon: const Icon(Icons.skip_next_rounded),
        ),
        IconButton(
          tooltip: switch (repeat) {
            QueueRepeat.off => 'Repetir todas',
            QueueRepeat.all => 'Repetir una',
            QueueRepeat.one => 'No repetir',
          },
          color: repeat == QueueRepeat.off
              ? scheme.onSurfaceVariant
              : scheme.primary,
          onPressed: () => handler.setRepeat(switch (repeat) {
            QueueRepeat.off => QueueRepeat.all,
            QueueRepeat.all => QueueRepeat.one,
            QueueRepeat.one => QueueRepeat.off,
          }),
          icon: Icon(
            repeat == QueueRepeat.one
                ? Icons.repeat_one_rounded
                : Icons.repeat_rounded,
          ),
        ),
      ],
    );
  }
}
