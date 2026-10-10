import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'features/player/data/sympho_audio_handler.dart';
import 'features/player/presentation/player_providers.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final audioHandler = SymphoAudioHandler();
  runApp(
    ProviderScope(
      overrides: [audioHandlerProvider.overrideWithValue(audioHandler)],
      child: const SymphoApp(),
    ),
  );
}
