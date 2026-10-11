import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_info.dart';
import '../../../core/utils/formatters.dart';
import '../../equalizer/presentation/equalizer_providers.dart';
import '../../equalizer/presentation/equalizer_screen.dart';
import '../../library/domain/library_grouping.dart';
import '../../library/presentation/widgets/screen_title.dart';
import '../../lyrics/data/lyrics_folder_access.dart';
import '../../lyrics/presentation/lyrics_providers.dart';
import '../data/app_preferences.dart';

/// Espacio que ocupa la caché temporal de letras.
final lyricsCacheSizeProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.watch(lyricsDiskCacheProvider).sizeBytes(),
);

/// Carpetas concedidas para leer archivos `.lrc`.
final lyricsFoldersProvider = FutureProvider.autoDispose<List<LyricsFolder>>(
  (ref) => ref.watch(lyricsFolderAccessProvider).folders(),
);

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: const [
            ScreenTitle('Ajustes'),
            _SectionHeader('Apariencia'),
            _ThemeSetting(),
            _SectionHeader('Sonido'),
            _EqualizerTile(),
            _SectionHeader('Letras'),
            _LyricsCacheSettings(),
            _LyricsFolderSettings(),
            _SectionHeader('Acerca de'),
            ListTile(
              leading: Icon(Icons.info_outline_rounded),
              title: Text(AppInfo.name),
              subtitle: Text(
                'Versión ${AppInfo.version} · Letras en línea de LRCLIB',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ThemeSetting extends ConsumerWidget {
  const _ThemeSetting();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(preferencesProvider.select((p) => p.themeMode));
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Tema', style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto_rounded),
                  label: Text('Sistema'),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode_rounded),
                  label: Text('Claro'),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode_rounded),
                  label: Text('Oscuro'),
                ),
              ],
              selected: {mode},
              onSelectionChanged: (selection) => ref
                  .read(preferencesProvider.notifier)
                  .setThemeMode(selection.first),
            ),
          ),
        ],
      ),
    );
  }
}

class _EqualizerTile extends ConsumerWidget {
  const _EqualizerTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(equalizerStateProvider).value?.settings;
    return ListTile(
      leading: const Icon(Icons.graphic_eq_rounded),
      title: const Text('Ecualizador'),
      subtitle: Text(
        settings == null || !settings.enabled
            ? 'Desactivado'
            : 'Activado · ${settings.preset.label}',
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => openEqualizerScreen(context),
    );
  }
}

class _LyricsCacheSettings extends ConsumerWidget {
  const _LyricsCacheSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saveToDisk = ref.watch(
      preferencesProvider.select((p) => p.saveLyricsToDisk),
    );
    final size = ref.watch(lyricsCacheSizeProvider).value ?? 0;

    Future<void> clearCache({bool notify = true}) async {
      final messenger = ScaffoldMessenger.of(context);
      await ref.read(lyricsDiskCacheProvider).clear();
      ref.invalidate(lyricsCacheSizeProvider);
      if (!notify) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Caché de letras borrada')),
        );
    }

    return Column(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.save_outlined),
          title: const Text('No guardar letras'),
          subtitle: const Text(
            'Las letras descargadas solo se conservan mientras la app está '
            'abierta.',
          ),
          value: !saveToDisk,
          onChanged: (noSave) async {
            await ref
                .read(preferencesProvider.notifier)
                .setSaveLyricsToDisk(!noSave);
            // Activar la opción elimina también lo que ya hubiera en disco.
            if (noSave) await clearCache(notify: false);
          },
        ),
        ListTile(
          leading: const Icon(Icons.delete_outline_rounded),
          title: const Text('Borrar caché de letras'),
          subtitle: Text(size == 0 ? 'Vacía' : '${formatBytes(size)} en uso'),
          enabled: size > 0,
          onTap: clearCache,
        ),
      ],
    );
  }
}

class _LyricsFolderSettings extends ConsumerWidget {
  const _LyricsFolderSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(lyricsFoldersProvider).value ?? const [];
    final access = ref.read(lyricsFolderAccessProvider);

    void refresh() {
      ref.invalidate(lyricsFoldersProvider);
      // Las letras ya buscadas pueden cambiar con el nuevo acceso.
      ref.read(lyricsRepositoryProvider).clearMemory();
      ref.invalidate(currentLyricsProvider);
    }

    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.folder_open_rounded),
          title: const Text('Acceso a archivos .lrc'),
          subtitle: const Text(
            'Android no deja leer los .lrc que acompañan a tus canciones '
            'sin tu permiso. Elige la carpeta donde guardas la música.',
          ),
          isThreeLine: true,
          trailing: IconButton.filledTonal(
            tooltip: 'Dar acceso a una carpeta',
            icon: const Icon(Icons.add_rounded),
            onPressed: () async {
              if (await access.pickFolder()) refresh();
            },
          ),
        ),
        for (final folder in folders)
          ListTile(
            contentPadding: const EdgeInsets.only(left: 72, right: 16),
            title: Text(
              _label(folder),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: const Text('Con acceso'),
            trailing: IconButton(
              tooltip: 'Quitar acceso',
              icon: const Icon(Icons.close_rounded),
              onPressed: () async {
                await access.releaseFolder(folder.uri);
                refresh();
              },
            ),
          ),
      ],
    );
  }

  String _label(LyricsFolder folder) {
    final path = folderDisplayPath(folder.path);
    return path.isEmpty ? 'Almacenamiento interno' : path;
  }
}
