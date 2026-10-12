/// Datos de la app que se necesitan en tiempo de ejecución.
abstract final class AppInfo {
  static const String name = 'SymphoPK';

  /// Debe coincidir con `version` en `pubspec.yaml` (hay un test que lo
  /// comprueba).
  static const String version = '1.3.3';

  static const String repositoryUrl =
      'https://github.com/Carlos-Avellaneda-2/SymphoPK';

  /// Identificación ante servicios externos, con el formato que pide LRCLIB:
  /// nombre, versión y enlace al proyecto.
  static const String userAgent = '$name/$version ($repositoryUrl)';
}
