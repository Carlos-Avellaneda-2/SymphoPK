import 'package:flutter/material.dart';

import 'core/permissions/permission_gate.dart';
import 'core/theme/app_theme.dart';

class SymphoApp extends StatelessWidget {
  const SymphoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SymphoPK',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const PermissionGate(
        child: Scaffold(body: Center(child: Text('SymphoPK'))),
      ),
    );
  }
}
