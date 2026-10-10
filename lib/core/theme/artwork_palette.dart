import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:palette_generator_master/palette_generator_master.dart';

/// Deriva un esquema Material 3 oscuro a partir de los colores de una
/// carátula. Devuelve `null` si la imagen no se puede analizar.
Future<ColorScheme?> colorSchemeFromArtwork(Uint8List bytes) async {
  try {
    final palette = await PaletteGeneratorMaster.fromImageProvider(
      // Una versión reducida basta para extraer colores y es mucho más rápida.
      ResizeImage(MemoryImage(bytes), width: 96, height: 96),
      maximumColorCount: 12,
      generateHarmony: false,
    );
    // Se prefiere un color vivo; si la carátula es apagada, el dominante.
    final seed =
        (palette.vibrantColor ??
                palette.lightVibrantColor ??
                palette.dominantColor ??
                palette.mutedColor)
            ?.color;
    if (seed == null) return null;
    return ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);
  } on Object {
    return null;
  }
}
