import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/notifications/app_notifications.dart';
import '../shared/providers/app_providers.dart';
import 'router.dart';
import 'theme/app_theme.dart';

class StrollWiseApp extends ConsumerStatefulWidget {
  const StrollWiseApp({super.key});

  @override
  ConsumerState<StrollWiseApp> createState() => _StrollWiseAppState();
}

class _StrollWiseAppState extends ConsumerState<StrollWiseApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(restoreAuthFromPrefs(ref));
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'StrollWise',
      theme: buildAppTheme(),
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
