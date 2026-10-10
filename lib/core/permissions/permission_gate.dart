import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'audio_permission_controller.dart';
import 'audio_permission_service.dart';

/// Muestra [child] solo cuando hay permiso de lectura de audio; en caso
/// contrario explica por qué hace falta y cómo concederlo.
class PermissionGate extends ConsumerStatefulWidget {
  const PermissionGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends ConsumerState<PermissionGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // El usuario puede haber concedido el permiso desde Ajustes.
    if (state != AppLifecycleState.resumed) return;
    final current = ref.read(audioPermissionProvider).value;
    if (current != null && current != AudioPermissionStatus.granted) {
      ref.read(audioPermissionProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final permission = ref.watch(audioPermissionProvider);
    final status = permission.value;
    if (status == AudioPermissionStatus.granted) return widget.child;
    if (status == null && !permission.hasError) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return PermissionDeniedView(
      permanentlyDenied:
          status == AudioPermissionStatus.permanentlyDenied ||
          permission.hasError,
      onRequest: ref.read(audioPermissionProvider.notifier).request,
      onOpenSettings: ref.read(audioPermissionProvider.notifier).openSettings,
    );
  }
}

class PermissionDeniedView extends StatelessWidget {
  const PermissionDeniedView({
    super.key,
    required this.permanentlyDenied,
    required this.onRequest,
    required this.onOpenSettings,
  });

  final bool permanentlyDenied;
  final VoidCallback onRequest;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.library_music_outlined,
                  size: 72,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  'Necesitamos acceso a tu música',
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  permanentlyDenied
                      ? 'El permiso está bloqueado. Ábrelo en Ajustes > '
                            'Permisos > Música y audio para que SymphoPK '
                            'pueda mostrar tus canciones.'
                      : 'SymphoPK solo lee los archivos de audio de tu '
                            'dispositivo para mostrarlos y reproducirlos. '
                            'Nada sale de tu teléfono.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: permanentlyDenied ? onOpenSettings : onRequest,
                  icon: Icon(
                    permanentlyDenied ? Icons.settings : Icons.check_circle,
                  ),
                  label: Text(
                    permanentlyDenied ? 'Abrir ajustes' : 'Conceder permiso',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
