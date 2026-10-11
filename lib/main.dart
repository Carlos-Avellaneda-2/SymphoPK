import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'features/player/data/player_widget_sync.dart';
import 'features/player/data/sympho_audio_handler.dart';
import 'features/player/presentation/player_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Registra el servicio en primer plano: a partir de aquí la reproducción
  // sobrevive a la app en segundo plano y aparece en la notificación y en
  // la pantalla de bloqueo.
  final audioHandler = await AudioService.init(
    builder: () => SymphoAudioHandler(),
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

  // Mantiene al día los widgets de la pantalla de inicio y atiende sus
  // botones, también con la app en segundo plano.
  PlayerWidgetSync(audioHandler).start();

  runApp(
    ProviderScope(
      overrides: [audioHandlerProvider.overrideWithValue(audioHandler)],
      child: const SymphoApp(),
    ),
  );
}
