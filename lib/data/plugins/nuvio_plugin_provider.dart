import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/stream_candidate.dart';
import '../../domain/resolution/provider_resolver.dart';
import 'nuvio_plugin_repository.dart';
import 'nuvio_plugin_runtime.dart';

final nuvioPluginProviderResolverProvider = Provider<NuvioPluginProviderResolver>((ref) {
  return NuvioPluginProviderResolver(
    repository: ref.read(nuvioPluginRepositoryProvider),
    runtime: ref.read(nuvioPluginRuntimeProvider),
  );
});

class NuvioPluginProviderResolver extends ProviderResolver {
  final NuvioPluginRepository repository;
  final NuvioPluginRuntime runtime;

  const NuvioPluginProviderResolver({required this.repository, required this.runtime});

  @override
  String get id => 'nuvio-plugins';

  @override
  String get displayName => 'Plugins compatibles Nuvio';

  @override
  int get priority => 12;

  @override
  Set<String> get supportedMediaTypes => const {'movie', 'tv', 'anime'};

  @override
  Future<List<StreamCandidate>> resolve(ProviderResolveRequest request) async {
    final plugins = (await repository.load())
        .where((plugin) => plugin.enabled && plugin.supports(request.mediaType))
        .toList(growable: false);
    if (plugins.isEmpty) return const [];

    final batches = await Future.wait([
      for (final plugin in plugins)
        runtime.resolve(plugin, request).catchError((_) => <StreamCandidate>[]),
    ]);
    final seen = <String>{};
    return [
      for (final batch in batches)
        for (final candidate in batch)
          if (seen.add(candidate.uri.toString())) candidate,
    ];
  }
}
