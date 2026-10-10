import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/formatters.dart';
import '../../../library/domain/song.dart';
import '../../domain/playlist.dart';
import '../playlist_providers.dart';

/// Pide un nombre de lista. Devuelve `null` si se cancela.
Future<String?> showPlaylistNameDialog(
  BuildContext context, {
  required String title,
  String initialName = '',
  String confirmLabel = 'Guardar',
}) {
  return showDialog<String>(
    context: context,
    useRootNavigator: true,
    builder: (_) => _NameDialog(
      title: title,
      initialName: initialName,
      confirmLabel: confirmLabel,
    ),
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.initialName,
    required this.confirmLabel,
  });

  final String title;
  final String initialName;
  final String confirmLabel;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _controller = TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isNotEmpty) Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 100,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Nombre de la lista'),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _controller.text.trim().isEmpty ? null : _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// Flujo completo de crear una lista. Devuelve su id o `null` si se cancela.
Future<int?> createPlaylistFlow(BuildContext context, WidgetRef ref) async {
  final name = await showPlaylistNameDialog(
    context,
    title: 'Nueva lista',
    confirmLabel: 'Crear',
  );
  if (name == null) return null;
  return ref.read(playlistRepositoryProvider).create(name);
}

Future<void> renamePlaylistFlow(
  BuildContext context,
  WidgetRef ref,
  Playlist playlist,
) async {
  final name = await showPlaylistNameDialog(
    context,
    title: 'Renombrar lista',
    initialName: playlist.name,
  );
  if (name == null) return;
  await ref.read(playlistRepositoryProvider).rename(playlist.id, name);
}

/// Pide confirmación y elimina. Devuelve `true` si la lista se eliminó.
Future<bool> deletePlaylistFlow(
  BuildContext context,
  WidgetRef ref,
  Playlist playlist,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    useRootNavigator: true,
    builder: (context) => AlertDialog(
      title: const Text('Eliminar lista'),
      content: Text(
        '¿Eliminar «${playlist.name}»? Las canciones seguirán en tu '
        'biblioteca.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Eliminar'),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;
  await ref.read(playlistRepositoryProvider).delete(playlist.id);
  return true;
}

/// Hoja para elegir a qué lista añadir [song], con opción de crear una.
Future<void> showAddToPlaylistSheet(
  BuildContext context,
  WidgetRef ref,
  Song song,
) {
  final messenger = ScaffoldMessenger.of(context);

  Future<void> add(int playlistId, String name) async {
    final added = await ref
        .read(playlistRepositoryProvider)
        .addSong(playlistId, song.id);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(added ? 'Añadida a «$name»' : 'Ya estaba en «$name»'),
        ),
      );
  }

  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => Consumer(
      builder: (_, sheetRef, _) {
        final playlists = sheetRef.watch(playlistsProvider).value ?? const [];
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.6,
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  leading: const Icon(Icons.add_rounded),
                  title: const Text('Nueva lista'),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    final name = await showPlaylistNameDialog(
                      context,
                      title: 'Nueva lista',
                      confirmLabel: 'Crear',
                    );
                    if (name == null) return;
                    final id = await ref
                        .read(playlistRepositoryProvider)
                        .create(name);
                    await add(id, name);
                  },
                ),
                for (final playlist in playlists)
                  ListTile(
                    leading: const Icon(Icons.queue_music_rounded),
                    title: Text(
                      playlist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(songCountLabel(playlist.songIds.length)),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      add(playlist.id, playlist.name);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
