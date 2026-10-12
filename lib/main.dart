import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/config/potv_runtime_flags.dart';
import 'core/config/potv_signed_flag_updater.dart';

import 'app/potv_app.dart';
import 'data/bootstrap/default_manifest_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  final preferences = await SharedPreferences.getInstance();
  final runtimeFlags = PotvRuntimeFlagStore(preferences)..load();
  final container = ProviderContainer(overrides: [
    potvRuntimeFlagStoreProvider.overrideWith((ref) => runtimeFlags),
  ]);
  await container.read(defaultManifestBootstrapProvider).load();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const PotvApp(),
    ),
  );

  // Do not delay startup or change offline behavior when configuration is absent.
  final flagsClient = http.Client();
  final updater = createConfiguredFlagUpdater(
    store: runtimeFlags,
    client: flagsClient,
  );
  if (updater == null) {
    flagsClient.close();
  } else {
    unawaited(updater.refresh().whenComplete(flagsClient.close));
  }
}
