import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'shared/providers/app_providers.dart';
import 'shared/traveler_gradient.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ZoneCatalog.ensureLoaded();

  // Load saved login before the router runs (avoids "logged out" flash).
  final container = ProviderContainer();
  await bootstrapAuthSession(container);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const StrollWiseApp(),
    ),
  );
}
