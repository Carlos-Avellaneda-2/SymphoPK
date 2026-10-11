# SymphoPK

Reproductor de música local para Android hecho con Flutter. Escanea el audio
almacenado en el dispositivo y lo reproduce con soporte de segundo plano,
notificación multimedia y controles en la pantalla de bloqueo.

## Descarga

El APK de cada versión está en la página de
[Releases](https://github.com/Carlos-Avellaneda-2/SymphoPK/releases/latest).
Descárgalo en el teléfono y ábrelo; Android pedirá permitir la instalación
desde orígenes desconocidos. Requiere Android 7.0 o superior y se instala
encima de versiones anteriores conservando listas, favoritos y la última
sesión.

## Funcionalidades

- **Biblioteca**: todas las canciones, vistas por carpeta, por álbum y por
  artista, y búsqueda por título o artista.
- **Carpetas**: explorador anidado de las carpetas del dispositivo que
  contienen música, sin necesidad de crear listas a mano. Se puede
  reproducir una carpeta entera, subcarpetas incluidas.
- **Widgets** para la pantalla de inicio en dos tamaños (4×1 y 3×2), con
  carátula, título y controles de anterior, play/pausa y siguiente.
- **Ecualizador** con las bandas del dispositivo, preajustes, refuerzo de
  volumen y configuración persistente.
- **Letras sincronizadas**: desde un archivo `.lrc`, desde los metadatos
  del archivo o desde LRCLIB, con la línea actual resaltada.
- **Ajustes**: tema (sistema, claro u oscuro), ecualizador y opciones de
  letras.
- **Reproductor**: play/pausa, siguiente, anterior, barra de progreso con
  seek, cola reordenable, modo aleatorio y repetir (ninguna / todas / una).
- **Mini reproductor** persistente y **pantalla completa** con la carátula
  como protagonista: fondo difuminado y colores extraídos de la propia
  carátula.
- **Segundo plano**: notificación multimedia, pantalla de bloqueo y botones
  de auriculares o Bluetooth. Pausa en llamadas y al desconectar auriculares.
- **Listas de reproducción**: crear, renombrar, eliminar, añadir y quitar
  canciones.
- **Favoritos**.
- **Continuar donde lo dejaste**: recuerda la cola, la canción y la posición.
- **Tema claro y oscuro** según el sistema, con Material 3.

## Uso

### Carpetas

La pestaña **Carpetas** de la biblioteca recorre el almacenamiento como un
explorador de archivos. Empieza en la primera carpeta donde la música se
ramifica (normalmente `Music`) y solo muestra carpetas que contienen
canciones, directamente o más adentro.

- Tocar una carpeta entra en ella; primero aparecen sus subcarpetas y
  después sus canciones, ordenadas por título.
- Los botones de la barra superior reproducen **toda** la carpeta,
  subcarpetas incluidas, en orden o en aleatorio.
- Tocar una canción reproduce solo las canciones de esa carpeta.

### Widgets

Mantén pulsada la pantalla de inicio, entra en **Widgets** y busca
SymphoPK. Hay dos tamaños:

| Widget | Contenido |
| --- | --- |
| 4×1 | Carátula, título, artista y controles en una fila |
| 3×2 | Carátula grande, título, artista y controles |

Los botones (anterior, play/pausa, siguiente) actúan sobre la música en
curso sin abrir la app. Tocar la carátula o el texto abre SymphoPK.

### Ecualizador

Se abre desde **Ajustes > Ecualizador** o con el icono de ondas del
reproductor. El número de bandas, sus frecuencias y el rango de ganancia
los informa cada dispositivo, así que la pantalla puede variar de un
teléfono a otro. Hace falta haber cargado una canción para que el
dispositivo informe de sus bandas.

Mover cualquier deslizador cambia el preajuste a **Personalizado**. El
refuerzo de volumen está limitado a 10 dB para evitar distorsión.

### Letras

En el reproductor, el botón de letra (junto al corazón) alterna entre la
carátula y la letra. La app la busca en este orden:

1. Un archivo `.lrc` con el mismo nombre que la canción y en su misma
   carpeta.
2. La letra incrustada en los metadatos del archivo.
3. [LRCLIB](https://lrclib.net), un servicio gratuito y sin registro. De una
   misma canción suele haber varias versiones con tiempos distintos; se
   elige la que coincide en título y artista y cuya duración es la más
   cercana a la de tu archivo (como mucho 3 segundos de diferencia). Los
   registros con tiempos claramente inventados se descartan.

Si la letra tiene marcas de tiempo, la línea actual se resalta y queda
centrada; tocar una línea salta a ese momento. Al desplazar a mano, el
seguimiento se pausa unos segundos.

Para que la app pueda leer tus archivos `.lrc` en Android 11 o superior
hay que concederle la carpeta de la música una vez, en
**Ajustes > Letras > Acceso a archivos .lrc**. El permiso de música no
basta porque un `.lrc` no es un archivo de audio.

Las letras descargadas no se guardan de forma permanente: se mantienen en
memoria y en la caché temporal de la app (7 días sin uso, 5 MB como
máximo). **Ajustes > Letras** permite no guardarlas en disco y vaciar la
caché.

## Estado

Versión actual: **1.3.1**. Todas las funciones se han probado a mano en un
teléfono Android real, además de los tests automáticos; la lista de lo
comprobado está en [Probado en un dispositivo real](#probado-en-un-dispositivo-real).
El detalle de cada versión está en [CHANGELOG.md](CHANGELOG.md).

| Versión | Cambios |
| --- | --- |
| [1.3.1](https://github.com/Carlos-Avellaneda-2/SymphoPK/releases/tag/v1.3.1) | Las letras de LRCLIB se eligen por título, artista y duración, y se descartan las de tiempos inventados |
| [1.3.0](https://github.com/Carlos-Avellaneda-2/SymphoPK/releases/tag/v1.3.0) | Ecualizador, letras sincronizadas y pantalla de ajustes con selección de tema |
| [1.2.0](https://github.com/Carlos-Avellaneda-2/SymphoPK/releases/tag/v1.2.0) | Navegación anidada por carpetas y widgets de pantalla de inicio (4×1 y 3×2) |
| [1.1.0](https://github.com/Carlos-Avellaneda-2/SymphoPK/releases/tag/v1.1.0) | Vista de la biblioteca por carpetas |
| [1.0.0](https://github.com/Carlos-Avellaneda-2/SymphoPK/releases/tag/v1.0.0) | Primera versión: biblioteca, reproductor, segundo plano, listas, favoritos y sesión |

Limitaciones conocidas:

- El ecualizador usa los efectos de audio de Android; algunos dispositivos
  no los ofrecen o los aplican de forma distinta.
- Los widgets controlan la reproducción mientras la app sigue en marcha
  (abierta o con música en segundo plano). Si el sistema la ha cerrado, el
  primer toque abre la app en lugar de reproducir.
- La biblioteca lista archivos: si la misma canción está copiada dos veces
  en el dispositivo, aparece dos veces.
- Las canciones de una lista no se pueden reordenar desde la interfaz (la
  cola de reproducción sí).
- La carátula en la notificación solo se muestra en Android 10 o superior.
- El APK de release se firma con la clave de depuración: sirve para uso
  personal, no para publicar en Google Play.

## Requisitos

| Herramienta | Versión |
| --- | --- |
| Flutter | 3.47 o superior (canal stable) |
| Dart | 3.13 o superior |
| JDK | 17 o superior |
| Android SDK | Plataforma 37 (compileSdk), mínimo Android 7.0 (API 24) |

El proyecto usa Android Gradle Plugin 9.2.1 y Gradle 9.4.1; el wrapper los
descarga solo. iOS no está implementado todavía, pero el código que depende
de la plataforma queda aislado (ver [Arquitectura](#arquitectura)).

## Cómo ejecutar

```bash
flutter pub get
flutter run            # con un dispositivo o emulador Android conectado
```

`flutter run` instala una versión de depuración, que sigue funcionando al
desconectar el teléfono pero es más lenta y pesada. Para el uso diario
conviene instalar la de release:

```bash
flutter run --release
```

Otros comandos útiles:

```bash
flutter analyze                    # análisis estático (flutter_lints)
flutter test                       # tests unitarios
flutter build apk --release        # APK de release
dart run build_runner build        # regenerar el código de Drift
```

Los tests de `test/ui` montan las pantallas con datos falsos y fallan si
algo desborda. Con la variable `SCREENSHOT_DIR` además guardan una captura
PNG de cada pantalla, útil para revisar el diseño sin dispositivo:

```bash
SCREENSHOT_DIR=capturas flutter test test/ui
```

El código generado por Drift (`app_database.g.dart`) está versionado, así que
solo hay que regenerarlo al cambiar las tablas.

Para probar la app hace falta música en el dispositivo. En un emulador se
puede copiar con:

```bash
adb push cancion.mp3 /sdcard/Music/
```

y después deslizar hacia abajo en la pestaña **Canciones** para reescanear.

## Paquetes principales

| Paquete | Uso |
| --- | --- |
| `just_audio` | Motor de reproducción |
| `audio_service` | Servicio en primer plano, notificación y botones multimedia |
| `audio_session` | Foco de audio (llamadas, desconexión de auriculares) |
| `permission_handler` + `device_info_plus` | Permisos según la versión de Android |
| `flutter_riverpod` | Gestión de estado |
| `drift` + `drift_flutter` | Persistencia en SQLite |
| `palette_generator_master` | Colores a partir de la carátula |
| `google_fonts` | Tipografía Manrope |
| `http` | Consultas a LRCLIB |
| `audio_metadata_reader` | Letras incrustadas en los archivos de audio |

**Lectura de la biblioteca**: no se usa ningún paquete. `MediaLibraryChannel.kt`
consulta MediaStore, que ya tiene indexados título, artista, álbum, duración
y carátula, y lo expone a Dart por un canal de plataforma; así no hay que
recorrer el almacenamiento ni leer las etiquetas de cada archivo. Se probó
`on_audio_query_pluse` (el fork mantenido de `on_audio_query`), pero exige
el permiso de fotos además del de audio y falla si no se concede. El acceso
queda detrás de la interfaz `LibraryScanner`, así que añadir iOS o cambiar
de implementación solo afecta a un archivo.

## Arquitectura

Organización por *features*, cada una con sus capas `data` / `domain` /
`presentation`. La UI nunca toca el reproductor directamente: habla con
`SymphoAudioHandler` y escucha su estado a través de providers de Riverpod.

```
lib/
├── main.dart                  Arranque: inicia audio_service e inyecta el handler
├── app.dart                   MaterialApp y temas
├── core/
│   ├── database/              Base de datos Drift (tablas y provider)
│   ├── permissions/           Permiso de audio por versión de Android y pantalla de aviso
│   ├── theme/                 Tema Material 3 y paleta a partir de la carátula
│   ├── utils/                 Formateadores
│   └── widgets/               Widgets genéricos
└── features/
    ├── equalizer/
    │   ├── data/              EqualizerController y EqualizerEngine (efectos de just_audio)
    │   ├── domain/            Preajustes como curvas y su mapeo a las bandas
    │   └── presentation/      Pantalla del ecualizador
    ├── home/                  Estructura con navegación inferior y mini reproductor
    ├── library/
    │   ├── data/              LibraryScanner (MediaStore) y caché de carátulas
    │   ├── domain/            Song, Album, Artist, Folder y agrupación/búsqueda
    │   └── presentation/      Biblioteca, detalle de álbum/artista/carpeta, widgets comunes
    ├── lyrics/
    │   ├── data/              Fuentes (.lrc, metadatos, LRCLIB), caché y repositorio
    │   ├── domain/            Modelo de letra, parser LRC y selección de coincidencia
    │   └── presentation/      Panel de letras
    ├── player/
    │   ├── data/              SymphoAudioHandler, persistencia de la sesión y
    │   │                      sincronización con los widgets
    │   ├── domain/            QueueManager (cola, aleatorio, repetir) y sesión
    │   └── presentation/      Mini reproductor, pantalla completa, cola
    ├── playlists/
    │   ├── data/              PlaylistRepository (Drift)
    │   ├── domain/            Playlist
    │   └── presentation/      Listas, detalle y diálogos
    ├── favorites/
    │   ├── data/              FavoritesRepository (Drift)
    │   └── presentation/      Pantalla y botón de favorito
    └── settings/
        ├── data/              Preferencias de la app (tema, guardado de letras)
        └── presentation/      Pantalla de ajustes
test/                          Tests de cola, repositorios, sesión, biblioteca, permisos
                               y pruebas de humo de las pantallas
android/                       Proyecto Android: manifest con el servicio mediaPlayback,
                               MediaLibraryChannel.kt (lectura de MediaStore) y los
                               widgets nativos (PlayerWidget*.kt y sus layouts)
```

Decisiones a tener en cuenta:

- **`QueueManager` es Dart puro**: decide qué canción va después (aleatorio,
  repetir, reordenar) sin depender de ningún plugin, y por eso se puede
  probar sin dispositivo.
- **Las canciones no se guardan en la base de datos**: se leen de MediaStore
  en cada arranque. Listas, favoritos y la última sesión guardan solo ids; si
  una canción se borra del dispositivo simplemente deja de aparecer.
- **Las carpetas se derivan de la ruta de cada archivo**: `buildFolderTree`
  construye el árbol con funciones puras a partir de la lista de canciones;
  no se recorre el almacenamiento.
- **Los widgets son nativos** (`AppWidgetProvider` y `RemoteViews`).
  `PlayerWidgetSync` les envía la canción y el estado por un canal de
  plataforma y ejecuta las órdenes de sus botones. El enlace nativo vive
  mientras exista el motor de Flutter, no la actividad, por eso funcionan
  con la música en segundo plano.
- **Los preajustes del ecualizador son curvas por frecuencia**, no valores
  por banda: se interpolan a las bandas que tenga cada dispositivo.
- **Las letras nunca se guardan de forma permanente**: solo pasan por la
  memoria y por el directorio de caché, que el sistema puede vaciar.
- **Preparado para iOS**: lo específico de Android está en
  `MediaStoreScanner`, `AudioPermissionService`, `PlayerWidgetSync` y la
  carpeta `android/`.

## Permisos de Android

| Permiso | Motivo |
| --- | --- |
| `READ_MEDIA_AUDIO` | Leer la música en Android 13 o superior |
| `READ_EXTERNAL_STORAGE` (hasta API 32) | Leer la música en versiones anteriores |
| `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, `WAKE_LOCK` | Reproducción en segundo plano |
| `POST_NOTIFICATIONS` | Notificación multimedia en Android 13 o superior |
| `INTERNET` | Descargar la tipografía Manrope la primera vez y buscar letras en LRCLIB |

## Probado en un dispositivo real

Los tests automáticos cubren la lógica, pero estas partes dependen del
sistema y solo se pueden validar en un teléfono. Todas se han comprobado a
mano y funcionan correctamente:

- **Permisos**: el diálogo aparece en el primer arranque. Al negarlo se
  muestra la pantalla explicativa y, al negarlo dos veces, el botón pasa a
  «Abrir ajustes».
- **Biblioteca**: se escanea la música del dispositivo y se muestran las
  carátulas, también en la vista por carpetas.
- **Notificación y pantalla de bloqueo**: al salir de la app con música
  sonando aparecen la carátula y los botones de anterior, play/pausa y
  siguiente, también con el teléfono bloqueado.
- **Auriculares**: los botones del cable o Bluetooth controlan la
  reproducción y la música se pausa al desconectarlos.
- **Llamadas**: una llamada entrante pausa la música.
- **Widgets**: los de 4×1 y 3×2 muestran la canción actual y sus botones
  responden con la app en segundo plano.
- **Ecualizador**: los preajustes y los deslizadores cambian el sonido al
  instante y la configuración se conserva al reabrir la app.
- **Letras**: se cargan desde un archivo `.lrc` (tras conceder la carpeta),
  desde los metadatos del archivo y desde LRCLIB; sin conexión aparece el
  aviso correspondiente.
- **Tema**: el cambio entre sistema, claro y oscuro es inmediato y se
  conserva al reabrir.
- **Reanudar**: al cerrar la app en pausa y volver a abrirla aparece la
  misma canción en la misma posición.

El comportamiento puede variar en otros dispositivos, sobre todo el
ecualizador, que depende de los efectos de audio de cada fabricante. Esta
misma lista sirve para repetir la comprobación en otro teléfono.