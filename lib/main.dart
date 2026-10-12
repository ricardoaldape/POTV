import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'core/config/potv_runtime_flags.dart';
import 'core/config/potv_signed_flag_updater.dart';

import 'app/potv_app.dart';
import 'data/bootstrap/default_manifest_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  final preferences = await SharedPreferences.getInstance();
  // Stable, non-identifying random installation ID for gradual flag rollout
  // and existing Telegram device linking. It is never used as authentication.
  if (preferences.getString('potv_device_id')?.isEmpty ?? true) {
    await preferences.setString('potv_device_id', const Uuid().v4());
  }
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
    // Check when POTV starts and after returning to the foreground.
    // Do not wake the device in the background or poll on a timer.
    var lastAttempt = DateTime.fromMillisecondsSinceEpoch(0);
    var refreshing = false;

    Future<void> refreshIfDue() async {
      if (refreshing ||
          DateTime.now().difference(lastAttempt) < const Duration(hours: 6)) {
        return;
      }
      refreshing = true;
      lastAttempt = DateTime.now();
      try {
        await updater.refresh();
      } finally {
        refreshing = false;
      }
    }

    AppLifecycleListener(
      onResume: () => unawaited(refreshIfDue()),
    );
    unawaited(refreshIfDue());
  }
}
