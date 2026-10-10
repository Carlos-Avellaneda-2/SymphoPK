import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Temas Material 3 de la app. La pantalla del reproductor deriva su propio
/// esquema a partir de la carátula; el resto usa este color semilla.
abstract final class AppTheme {
  static const Color seed = Color(0xFF7C5CFF);

  static ThemeData light() => fromScheme(
    ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light),
  );

  static ThemeData dark() => fromScheme(
    ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    ).copyWith(surface: const Color(0xFF0F0F14)),
  );

  static ThemeData fromScheme(ColorScheme scheme) {
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      textTheme: _manrope(base.textTheme),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Aplica Manrope estilo a estilo. `google_fonts` 9 devuelve el `TextTheme`
  /// de `material_ui`, incompatible con el de `flutter/material.dart`, pero
  /// `TextStyle` es compartido; así cada peso carga su variante real.
  static TextTheme _manrope(TextTheme t) {
    TextStyle? f(TextStyle? style) =>
        style == null ? null : GoogleFonts.manrope(textStyle: style);
    return t.copyWith(
      displayLarge: f(t.displayLarge),
      displayMedium: f(t.displayMedium),
      displaySmall: f(t.displaySmall),
      headlineLarge: f(t.headlineLarge),
      headlineMedium: f(t.headlineMedium),
      headlineSmall: f(t.headlineSmall),
      titleLarge: f(t.titleLarge),
      titleMedium: f(t.titleMedium),
      titleSmall: f(t.titleSmall),
      bodyLarge: f(t.bodyLarge),
      bodyMedium: f(t.bodyMedium),
      bodySmall: f(t.bodySmall),
      labelLarge: f(t.labelLarge),
      labelMedium: f(t.labelMedium),
      labelSmall: f(t.labelSmall),
    );
  }
}
