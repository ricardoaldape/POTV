import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/stream_candidate.dart';
import '../../domain/resolution/provider_resolver.dart';
import '../anime/anime_id_mapping_service.dart';
import 'nuvio_plugin_repository.dart';
import 'nuvio_plugin_runtime.dart';

final nuvioPluginProviderResolverProvider = Provider<NuvioPluginProviderResolver>((ref) {
  return NuvioPluginProviderResolver(
    repository: ref.read(nuvioPluginRepositoryProvider),
    runtime: ref.read(nuvioPluginRuntimeProvider),
    animeMapping: ref.read(animeIdMappingServiceProvider),
  );
});

class NuvioPluginProviderResolver extends ProviderResolver {
  final NuvioPluginRepository repository;
  final NuvioPluginRuntime runtime;
  final AnimeIdMappingService animeMapping;

  const NuvioPluginProviderResolver({
    required this.repository,
    required this.runtime,
    required this.animeMapping,
  });

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
    var effectiveRequest = request;
    if (request.isAnime) {
      final anilistId = int.tryParse(request.mediaId);
      final absoluteEpisode = request.episode;
      if (anilistId == null || absoluteEpisode == null) return const [];
      final mapped = await animeMapping.mapEpisode(
        anilistId: anilistId,
        absoluteEpisode: absoluteEpisode,
        title: request.title,
      );
      if (mapped?.tmdbId == null) return const [];
      effectiveRequest = ProviderResolveRequest(
        mediaType: 'anime',
        mediaId: mapped!.tmdbId.toString(),
        externalId: mapped.imdbId,
        title: request.title,
        year: request.year,
        season: mapped.season,
        episode: mapped.episode ?? absoluteEpisode,
      );
    }

    final plugins = (await repository.load())
        .where((plugin) => plugin.enabled && plugin.supports(request.mediaType))
        .toList(growable: false);
    if (plugins.isEmpty) return const [];

    final batches = await Future.wait([
      for (final plugin in plugins)
        runtime.resolve(plugin, effectiveRequest).catchError((_) => <StreamCandidate>[]),
    ]);
    final seen = <String>{};
    return [
      for (final batch in batches)
        for (final candidate in batch)
          if (seen.add(candidate.uri.toString())) candidate,
    ];
  }
}
