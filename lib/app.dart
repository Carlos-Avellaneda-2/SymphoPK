import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/permissions/permission_gate.dart';
import 'core/theme/app_theme.dart';
import 'features/home/home_shell.dart';
import 'features/player/presentation/player_providers.dart';
import 'features/settings/data/app_preferences.dart';

class SymphoApp extends ConsumerWidget {
  const SymphoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Las preferencias de reproducción se aplican al servicio de audio en
    // cuanto cambian (los valores iniciales se aplican en main()).
    ref.listen(
      preferencesProvider.select((p) => p.normalization),
      (_, mode) => ref.read(audioHandlerProvider).setNormalization(mode),
    );

    return MaterialApp(
      title: 'SymphoPK',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // Sistema, claro u oscuro, según lo elegido en Ajustes.
      themeMode: ref.watch(preferencesProvider.select((p) => p.themeMode)),
      home: const PermissionGate(child: HomeShell()),
    );
  }
}
