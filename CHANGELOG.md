# Historial de cambios

Todas las versiones publicadas de SymphoPK. El formato sigue
[Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y las versiones,
[SemVer](https://semver.org/lang/es/).

## [1.3.1] - 2026-10-10

### Corregido

- **Letras de LRCLIB mal sincronizadas** cuando una canción tiene varias
  versiones. Antes se aceptaba la primera coincidencia que devolvía el
  servicio, que admite ±2 segundos y no siempre es la más cercana. Ahora se
  reúnen las versiones disponibles y se elige por título, artista y
  duración, comparando con precisión de milisegundos.
- **Letras con tiempos inventados.** LRCLIB tiene registros cuyas marcas
  de tiempo no corresponden al audio: líneas repartidas a intervalos
  idénticos desde el segundo cero, o que siguen después del final de la
  canción. Ahora se detectan y se descartan en favor de una versión
  sincronizada de verdad; si no hay otra, la letra se muestra como texto
  en lugar de resaltar la línea equivocada.
- La duración se enviaba truncada a segundos; ahora se redondea.
- Los resultados de otro título u otro artista se descartan aunque su
  duración coincida.

### Cambiado

- Las letras guardadas en la caché temporal con el criterio anterior dejan
  de usarse, para que se vuelvan a elegir con el nuevo.

## [1.3.0] - 2026-10-10

### Añadido

- **Ecualizador** con las bandas que ofrezca cada dispositivo: interruptor,
  un deslizador vertical por banda, preajustes (Plano, Pop, Rock, Jazz,
  Clásica, Bass Boost, Vocal y Personalizado), refuerzo de volumen de hasta
  10 dB y botón para restablecer. Los cambios se oyen al instante y la
  configuración se conserva entre sesiones. Se abre desde Ajustes o desde el
  reproductor.
- **Letras sincronizadas** en el reproductor. Se buscan, por este orden, en
  un archivo `.lrc` junto a la canción, en los metadatos del archivo y en
  [LRCLIB](https://lrclib.net). La línea actual se resalta y se mantiene
  centrada; tocar una línea salta a ese momento. Las letras sin marcas de
  tiempo se muestran como texto.
- **Ajustes**, como cuarta pestaña:
  - Tema de la app: sistema (por defecto), claro u oscuro.
  - Acceso al ecualizador.
  - «No guardar letras» y «Borrar caché de letras», con el espacio en uso.
  - Acceso a carpetas para leer archivos `.lrc`.

### Notas

- Las letras descargadas de LRCLIB no se guardan de forma permanente: viven
  en memoria durante la sesión y en la caché temporal de la app, que caduca
  a los 7 días sin uso y no pasa de 5 MB.
- Desde Android 11 el permiso de música no permite leer archivos `.lrc`.
  Para usarlos hay que conceder la carpeta de la música en
  Ajustes > Letras > Acceso a archivos .lrc.

## [1.2.0] - 2026-10-10

### Añadido

- Navegación anidada por carpetas, como en un explorador de archivos, con
  reproducción de una carpeta entera incluyendo sus subcarpetas.
- Widgets para la pantalla de inicio en dos tamaños (4×1 y 3×2) con
  carátula, título y controles.

## [1.1.0] - 2026-10-10

### Añadido

- Vista de la biblioteca por carpetas del dispositivo.

## [1.0.0] - 2026-10-10

### Añadido

- Biblioteca con canciones, álbumes y artistas, y búsqueda por título o
  artista.
- Reproductor con cola reordenable, modo aleatorio y repetir.
- Mini reproductor y pantalla completa con colores tomados de la carátula.
- Reproducción en segundo plano con notificación y controles en la pantalla
  de bloqueo.
- Listas de reproducción y favoritos.
- Recuerda la última canción y la posición al reabrir.
- Tema claro y oscuro según el sistema.

[1.3.1]: https://github.com/Carlos-Avellaneda-2/SymphoPK/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/Carlos-Avellaneda-2/SymphoPK/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/Carlos-Avellaneda-2/SymphoPK/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/Carlos-Avellaneda-2/SymphoPK/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/Carlos-Avellaneda-2/SymphoPK/releases/tag/v1.0.0
