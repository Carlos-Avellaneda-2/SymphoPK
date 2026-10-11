import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/presentation/widgets/empty_state.dart';
import '../data/equalizer_controller.dart';
import '../domain/equalizer_preset.dart';
import '../domain/equalizer_settings.dart';
import 'equalizer_providers.dart';

/// Abre el ecualizador por encima de toda la app (navegador raíz), para que
/// funcione igual desde Ajustes y desde el reproductor.
Future<void> openEqualizerScreen(BuildContext context) {
  return Navigator.of(
    context,
    rootNavigator: true,
  ).push(MaterialPageRoute<void>(builder: (_) => const EqualizerScreen()));
}

class EqualizerScreen extends ConsumerWidget {
  const EqualizerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(equalizerStateProvider).value;
    final controller = ref.read(equalizerControllerProvider);
    final enabled = state?.settings.enabled ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ecualizador'),
        actions: [
          IconButton(
            tooltip: 'Restablecer',
            onPressed: state?.isAvailable == true ? controller.reset : null,
            icon: const Icon(Icons.restart_alt_rounded),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Switch(
              value: enabled,
              onChanged: state?.isAvailable == true
                  ? controller.setEnabled
                  : null,
            ),
          ),
        ],
      ),
      body: state == null || !state.isAvailable
          ? const EmptyState(
              icon: Icons.graphic_eq_rounded,
              title: 'Ecualizador no disponible todavía',
              message:
                  'Reproduce una canción para que el dispositivo informe de '
                  'sus bandas. Si sigue sin aparecer, este dispositivo no '
                  'ofrece ecualizador.',
            )
          : _EqualizerBody(state: state, controller: controller),
    );
  }
}

class _EqualizerBody extends StatelessWidget {
  const _EqualizerBody({required this.state, required this.controller});

  final EqualizerState state;
  final EqualizerController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final settings = state.settings;
    final capabilities = state.capabilities!;
    final enabled = settings.enabled;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (!enabled)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Activa el interruptor para aplicar el ecualizador.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        Text('Preajuste', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final preset in EqualizerPreset.values)
              ChoiceChip(
                label: Text(preset.label),
                selected: settings.preset == preset,
                onSelected: enabled
                    ? (_) => controller.selectPreset(preset)
                    : null,
              ),
          ],
        ),
        const SizedBox(height: 24),
        Text('Bandas', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        SizedBox(
          height: 260,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var band = 0; band < capabilities.bandCount; band++)
                Expanded(
                  child: _BandSlider(
                    frequency: capabilities.centerFrequencies[band],
                    gain: state.gains[band],
                    min: capabilities.minDb,
                    max: capabilities.maxDb,
                    enabled: enabled,
                    onChanged: (gain) => controller.setBandGain(band, gain),
                    onChangeEnd: controller.commit,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Text(
                'Refuerzo de volumen',
                style: theme.textTheme.titleSmall,
              ),
            ),
            Text(
              formatGain(settings.loudnessDb),
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.primary,
              ),
            ),
          ],
        ),
        Slider(
          max: EqualizerSettings.maxLoudnessDb,
          divisions: EqualizerSettings.maxLoudnessDb.round(),
          value: settings.loudnessDb,
          label: formatGain(settings.loudnessDb),
          onChanged: enabled ? controller.setLoudness : null,
          onChangeEnd: (_) => controller.commit(),
        ),
        Text(
          'Sube el volumen por encima del máximo. Valores altos pueden '
          'distorsionar el sonido.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Deslizador vertical de una banda, con su ganancia arriba y su frecuencia
/// abajo.
class _BandSlider extends StatelessWidget {
  const _BandSlider({
    required this.frequency,
    required this.gain,
    required this.min,
    required this.max,
    required this.enabled,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final double frequency;
  final double gain;
  final double min;
  final double max;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final VoidCallback onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final labelStyle = theme.textTheme.labelSmall;
    return Column(
      children: [
        // Con muchas bandas las etiquetas se encogen en vez de cortarse.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            formatGain(gain),
            style: labelStyle?.copyWith(
              color: enabled ? scheme.primary : scheme.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        Expanded(
          child: RotatedBox(
            // El deslizador se gira para que «arriba» sea más ganancia.
            quarterTurns: 3,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: Slider(
                min: min,
                max: max,
                value: gain.clamp(min, max).toDouble(),
                semanticFormatterCallback: formatGain,
                onChanged: enabled ? onChanged : null,
                onChangeEnd: (_) => onChangeEnd(),
              ),
            ),
          ),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            formatFrequency(frequency),
            style: labelStyle?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
