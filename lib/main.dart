import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'app/potv_app.dart';
import 'data/bootstrap/default_manifest_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  final container = ProviderContainer();
  await container.read(defaultManifestBootstrapProvider).load();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const PotvApp(),
    ),
  );
}
