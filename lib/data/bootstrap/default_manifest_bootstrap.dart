import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../config/default_manifests.dart';
import '../sources/universal_source_installer.dart';

final defaultManifestBootstrapResultProvider =
    StateProvider<DefaultManifestBootstrapResult?>((ref) => null);

final defaultManifestBootstrapProvider = Provider<DefaultManifestBootstrap>((ref) {
  return DefaultManifestBootstrap(
    installer: ref.read(universalSourceInstallerProvider),
    ref: ref,
  );
});

class DefaultManifestBootstrapResult {
  final int attempted;
  final int installed;
  final Map<String, String> failures;

  const DefaultManifestBootstrapResult({
    required this.attempted,
    required this.installed,
    required this.failures,
  });
}

class DefaultManifestBootstrap {
  final UniversalSourceInstaller installer;
  final Ref ref;

  const DefaultManifestBootstrap({
    required this.installer,
    required this.ref,
  });

  Future<DefaultManifestBootstrapResult> load() async {
    var attempted = 0;
    var installed = 0;
    final failures = <String, String>{};
    final seen = <String>{};

    // Keep installs sequential. Repositories persist into the same local stores,
    // so parallel read/modify/write cycles could overwrite each other.
    for (final rawUrl in DefaultManifests.urls) {
      final url = rawUrl.trim();
      if (url.isEmpty || !seen.add(url)) continue;
      attempted++;
      debugPrint('[DefaultManifests] Intentando: $url');

      try {
        final result = await installer
            .install(url)
            .timeout(const Duration(seconds: 20));
        if (result.active) installed++;
        debugPrint(
          '[DefaultManifests] ÉXITO: $url '
          '(active=${result.active}, kind=${result.kind.name}, added=${result.added})',
        );
      } catch (error, stackTrace) {
        // A broken/offline default manifest must never prevent POTV from opening.
        failures[url] = error.toString();
        debugPrint('[DefaultManifests] ERROR: $url');
        debugPrint('[DefaultManifests] $error');
        debugPrint('[DefaultManifests] $stackTrace');
      }
    }

    final result = DefaultManifestBootstrapResult(
      attempted: attempted,
      installed: installed,
      failures: Map.unmodifiable(failures),
    );

    ref.read(defaultManifestBootstrapResultProvider.notifier).state = result;
    debugPrint(
      '[DefaultManifests] RESUMEN: attempted=${result.attempted}, '
      'installed=${result.installed}, failures=${result.failures}',
    );

    return result;
  }
}
