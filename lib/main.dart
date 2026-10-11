import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:just_audio/just_audio.dart';

import 'app.dart';
import 'core/database/app_database.dart';
import 'core/database/database_provider.dart';
import 'core/database/key_value_store.dart';
import 'features/equalizer/data/equalizer_controller.dart';
import 'features/equalizer/data/equalizer_engine.dart';
import 'features/equalizer/presentation/equalizer_providers.dart';
import 'features/player/data/player_widget_sync.dart';
import 'features/player/data/sympho_audio_handler.dart';
import 'features/player/presentation/player_providers.dart';
import 'features/settings/data/app_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final database = AppDatabase();
  final settingsStore = DriftKeyValueStore(database);
  // Se leen antes de pintar para arrancar ya con el tema elegido.
  final preferences = await AppPreferences.load(settingsStore);

  // Los efectos de audio se conectan al reproductor al crearlo, así que el
  // ecualizador tiene que existir antes que el servicio de audio.
  final equalizerEngine = JustAudioEqualizerEngine();
  final equalizer = EqualizerController(equalizerEngine, settingsStore);

  // Registra el servicio en primer plano: a partir de aquí la reproducción
  // sobrevive a la app en segundo plano y aparece en la notificación y en
  // la pantalla de bloqueo.
  final audioHandler = await AudioService.init(
    builder: () => SymphoAudioHandler(
      player: AudioPlayer(audioPipeline: equalizerEngine.pipeline),
    ),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.carlosavellaneda.symphopk.playback',
      androidNotificationChannelName: 'Reproducción',
      androidNotificationChannelDescription: 'Controles de la música en curso',
      androidNotificationIcon: 'drawable/ic_notification',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );
  await audioHandler.configureAudioSession();
  await equalizer.init();

  // Mantiene al día los widgets de la pantalla de inicio y atiende sus
  // botones, también con la app en segundo plano.
  PlayerWidgetSync(audioHandler).start();

  runApp(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        initialPreferencesProvider.overrideWithValue(preferences),
        audioHandlerProvider.overrideWithValue(audioHandler),
        equalizerControllerProvider.overrideWithValue(equalizer),
      ],
      child: const SymphoApp(),
    ),
  );
}
