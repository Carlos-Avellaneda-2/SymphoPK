# SymphoPK

Reproductor de música local para Android hecho con Flutter. Escanea el audio
almacenado en el dispositivo y lo reproduce con soporte de segundo plano,
notificación multimedia y controles en la pantalla de bloqueo.

## Funcionalidades

- **Biblioteca**: todas las canciones, vistas por álbum y por artista, y
  búsqueda por título o artista.
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
| `on_audio_query_pluse` | Lectura de la biblioteca desde MediaStore |
| `permission_handler` + `device_info_plus` | Permisos según la versión de Android |
| `flutter_riverpod` | Gestión de estado |
| `drift` + `drift_flutter` | Persistencia en SQLite |
| `palette_generator_master` | Colores a partir de la carátula |
| `google_fonts` | Tipografía Manrope |

**Por qué `on_audio_query_pluse`**: consulta MediaStore, que ya tiene
indexados título, artista, álbum, duración y carátula, así que no hay que
recorrer el almacenamiento ni leer las etiquetas de cada archivo. El paquete
original `on_audio_query` no se actualiza desde 2023; este fork sigue
publicando versiones. Como su uso es minoritario, queda detrás de la interfaz
`LibraryScanner`: sustituirlo solo afecta a un archivo.

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
    ├── home/                  Estructura con navegación inferior y mini reproductor
    ├── library/
    │   ├── data/              LibraryScanner (MediaStore) y caché de carátulas
    │   ├── domain/            Song, Album, Artist y agrupación/búsqueda
    │   └── presentation/      Biblioteca, detalle de álbum/artista, widgets comunes
    ├── player/
    │   ├── data/              SymphoAudioHandler y persistencia de la sesión
    │   ├── domain/            QueueManager (cola, aleatorio, repetir) y sesión
    │   └── presentation/      Mini reproductor, pantalla completa, cola
    ├── playlists/
    │   ├── data/              PlaylistRepository (Drift)
    │   ├── domain/            Playlist
    │   └── presentation/      Listas, detalle y diálogos
    └── favorites/
        ├── data/              FavoritesRepository (Drift)
        └── presentation/      Pantalla y botón de favorito
test/                          Tests de cola, repositorios, sesión, biblioteca y permisos
android/                       Proyecto Android (manifest con el servicio mediaPlayback)
```

Decisiones a tener en cuenta:

- **`QueueManager` es Dart puro**: decide qué canción va después (aleatorio,
  repetir, reordenar) sin depender de ningún plugin, y por eso se puede
  probar sin dispositivo.
- **Las canciones no se guardan en la base de datos**: se leen de MediaStore
  en cada arranque. Listas, favoritos y la última sesión guardan solo ids; si
  una canción se borra del dispositivo simplemente deja de aparecer.
- **Preparado para iOS**: lo específico de Android está en
  `OnAudioQueryScanner`, `AudioPermissionService` y la carpeta `android/`.

## Permisos de Android

| Permiso | Motivo |
| --- | --- |
| `READ_MEDIA_AUDIO` | Leer la música en Android 13 o superior |
| `READ_EXTERNAL_STORAGE` (hasta API 32) | Leer la música en versiones anteriores |
| `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, `WAKE_LOCK` | Reproducción en segundo plano |
| `POST_NOTIFICATIONS` | Notificación multimedia en Android 13 o superior |
| `INTERNET` | Descargar la tipografía Manrope la primera vez (queda en caché) |

## Qué hay que probar en un dispositivo real

Los tests cubren la lógica, pero estas partes dependen del sistema:

1. **Permisos**: en el primer arranque debe aparecer el diálogo. Al negarlo
   se muestra la pantalla explicativa; al negarlo dos veces, el botón pasa a
   «Abrir ajustes».
2. **Notificación y pantalla de bloqueo**: reproduce una canción, sal de la
   app y comprueba la notificación con carátula y los botones anterior,
   play/pausa y siguiente. Bloquea el teléfono y repite.
3. **Auriculares**: los botones del cable o Bluetooth deben controlar la
   reproducción, y al desconectarlos la música debe pausarse.
4. **Llamadas**: una llamada entrante debe pausar la música.
5. **Reanudar**: cierra la app desde recientes estando en pausa, vuelve a
   abrirla y comprueba que aparece la misma canción en la misma posición.
