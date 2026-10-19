import 'package:flutter/material.dart';

import '../../domain/audio_quality.dart';

/// Insignia con el formato y la calidad del archivo: `FLAC · 16 bit/44.1 kHz`,
/// `MP3 · 320 kbps`... No ocupa espacio si no se conoce el formato.
class QualityBadge extends StatelessWidget {
  const QualityBadge({super.key, required this.quality, this.compact = false});

  final AudioQuality quality;

  /// Versión más pequeña, para listas y menús.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final label = quality.label;
    if (label == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tier = quality.tier;
    final highlighted =
        tier == QualityTier.hiRes || tier == QualityTier.lossless;
    final foreground = switch (tier) {
      QualityTier.hiRes || QualityTier.lossless => scheme.onPrimaryContainer,
      QualityTier.low => scheme.onErrorContainer,
      _ => scheme.onSurfaceVariant,
    };
    final background = switch (tier) {
      QualityTier.hiRes || QualityTier.lossless => scheme.primaryContainer,
      QualityTier.low => scheme.errorContainer.withValues(alpha: 0.7),
      _ => scheme.surfaceContainerHighest.withValues(alpha: 0.7),
    };

    return Semantics(
      label: 'Calidad: $label',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 8,
          vertical: compact ? 1 : 3,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tier == QualityTier.hiRes) ...[
              Icon(
                Icons.high_quality_rounded,
                size: compact ? 12 : 14,
                color: foreground,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style:
                  (compact
                          ? theme.textTheme.labelSmall
                          : theme.textTheme.labelMedium)
                      ?.copyWith(
                        color: foreground,
                        fontWeight: highlighted
                            ? FontWeight.w700
                            : FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
            ),
          ],
        ),
      ),
    );
  }
}
