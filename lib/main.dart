import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'app/potv_app.dart';
import 'data/bootstrap/default_manifest_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  final container = ProviderContainer();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const PotvApp(),
    ),
  );

  // External manifests are optional catalog enrichment. Never hold the first
  // frame hostage to third-party network availability: boot POTV immediately
  // and hydrate those sources in the background.
  unawaited(container.read(defaultManifestBootstrapProvider).load());
}
