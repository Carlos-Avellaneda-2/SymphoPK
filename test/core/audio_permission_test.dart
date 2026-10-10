import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:symphopk/core/permissions/audio_permission_service.dart';
import 'package:symphopk/core/permissions/permission_gate.dart';

void main() {
  group('audioPermissionForSdk', () {
    test('usa READ_MEDIA_AUDIO desde Android 13', () {
      expect(audioPermissionForSdk(33), Permission.audio);
      expect(audioPermissionForSdk(36), Permission.audio);
    });

    test('usa READ_EXTERNAL_STORAGE en versiones anteriores', () {
      expect(audioPermissionForSdk(32), Permission.storage);
      expect(audioPermissionForSdk(24), Permission.storage);
    });
  });

  group('PermissionDeniedView', () {
    testWidgets('ofrece volver a pedir el permiso si es recuperable', (
      tester,
    ) async {
      var requested = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: PermissionDeniedView(
            permanentlyDenied: false,
            onRequest: () => requested++,
            onOpenSettings: () {},
          ),
        ),
      );
      await tester.tap(find.text('Conceder permiso'));
      expect(requested, 1);
    });

    testWidgets('envía a Ajustes si la negación es permanente', (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: PermissionDeniedView(
            permanentlyDenied: true,
            onRequest: () {},
            onOpenSettings: () => opened++,
          ),
        ),
      );
      await tester.tap(find.text('Abrir ajustes'));
      expect(opened, 1);
    });
  });
}
