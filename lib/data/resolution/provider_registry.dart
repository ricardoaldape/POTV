import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/resolution/provider_resolver.dart';
import '../addons/stremio_source_resolver.dart';
import '../anime/anime_id_mapping_service.dart';
import '../sources/http_source_resolver.dart';
import '../sources/public_domain_movie_resolver.dart';
import '../sources/public_domain_series_resolver.dart';
import 'provider_adapters.dart';

final providerRegistryProvider = Provider<List<ProviderResolver>>((ref) {
  final providers = <ProviderResolver>[
    StremioProviderResolver(
      resolver: ref.read(stremioSourceResolverProvider),
      animeMapping: ref.read(animeIdMappingServiceProvider),
    ),
    HttpProviderResolver(ref.read(httpSourceResolverProvider)),
    PublicDomainMovieProviderResolver(
      ref.read(publicDomainMovieResolverProvider),
    ),
    PublicDomainSeriesProviderResolver(
      ref.read(publicDomainSeriesResolverProvider),
    ),
  ];

  providers.sort((a, b) => a.priority.compareTo(b.priority));
  return List<ProviderResolver>.unmodifiable(providers);
});
