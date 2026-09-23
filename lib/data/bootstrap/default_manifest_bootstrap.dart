import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/default_manifests.dart';
import '../sources/universal_source_installer.dart';

final defaultManifestBootstrapProvider = Provider<DefaultManifestBootstrap>((ref) {
  return DefaultManifestBootstrap(
    installer: ref.read(universalSourceInstallerProvider),
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

  const DefaultManifestBootstrap({required this.installer});

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

      try {
        final result = await installer
            .install(url)
            .timeout(const Duration(seconds: 20));
        if (result.active) installed++;
      } catch (error) {
        // A broken/offline default manifest must never prevent POTV from opening.
        failures[url] = error.toString();
      }
    }

    return DefaultManifestBootstrapResult(
      attempted: attempted,
      installed: installed,
      failures: Map.unmodifiable(failures),
    );
  }
}
