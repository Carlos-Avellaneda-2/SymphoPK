import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// Estado simplificado del permiso de lectura de audio.
enum AudioPermissionStatus {
  granted,

  /// Negado, pero todavía se puede volver a mostrar el diálogo del sistema.
  denied,

  /// Negado de forma permanente: solo se puede conceder desde Ajustes.
  permanentlyDenied,
}

/// Android 13 (API 33) sustituyó `READ_EXTERNAL_STORAGE` por permisos
/// granulares; para música el correcto es `READ_MEDIA_AUDIO`.
Permission audioPermissionForSdk(int sdkInt) =>
    sdkInt >= 33 ? Permission.audio : Permission.storage;

/// Encapsula `permission_handler` para que el resto de la app no dependa
/// del plugin ni de la versión de Android.
class AudioPermissionService {
  AudioPermissionService({DeviceInfoPlugin? deviceInfo})
    : _deviceInfo = deviceInfo ?? DeviceInfoPlugin();

  final DeviceInfoPlugin _deviceInfo;
  Permission? _cached;

  Future<Permission> _permission() async {
    final cached = _cached;
    if (cached != null) return cached;
    final Permission permission;
    if (Platform.isAndroid) {
      final info = await _deviceInfo.androidInfo;
      permission = audioPermissionForSdk(info.version.sdkInt);
    } else {
      // Preparado para iOS: la biblioteca musical usa este permiso.
      permission = Permission.mediaLibrary;
    }
    return _cached = permission;
  }

  Future<AudioPermissionStatus> check() async =>
      _map(await (await _permission()).status);

  Future<AudioPermissionStatus> request() async =>
      _map(await (await _permission()).request());

  /// Pide el permiso de notificaciones (Android 13+). No es bloqueante: la
  /// notificación multimedia es opcional para usar la app.
  Future<void> requestNotifications() async {
    if (!Platform.isAndroid) return;
    final info = await _deviceInfo.androidInfo;
    if (info.version.sdkInt >= 33) await Permission.notification.request();
  }

  Future<bool> openSettings() => openAppSettings();

  AudioPermissionStatus _map(PermissionStatus status) {
    if (status.isGranted || status.isLimited) {
      return AudioPermissionStatus.granted;
    }
    if (status.isPermanentlyDenied || status.isRestricted) {
      return AudioPermissionStatus.permanentlyDenied;
    }
    return AudioPermissionStatus.denied;
  }
}
