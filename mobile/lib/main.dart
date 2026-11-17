import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router.dart';
import 'core/theme.dart';

void main() {
  runApp(const ProviderScope(child: HoopArchiveApp()));
}

class HoopArchiveApp extends StatelessWidget {
  const HoopArchiveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: MaterialApp.router(
        title: 'Hoop Archive',
        debugShowCheckedModeBanner: false,
        // The archive is a dark instrument panel by design; there is no light
        // variant to fall back to.
        theme: AppTheme.dark,
        themeMode: ThemeMode.dark,
        routerConfig: appRouter,
      ),
    );
  }
}
