import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/resolution/provider_resolver.dart';
import '../addons/stremio_source_resolver.dart';
import '../anime/anime_id_mapping_service.dart';
import '../plugins/nuvio_plugin_provider.dart';
import '../sources/http_source_resolver.dart';
import '../sources/public_domain_movie_resolver.dart';
import 'configured_resolver_catalog.dart';
import 'configured_resolver_provider.dart';
import 'provider_adapters.dart';

final providerRegistryProvider = Provider<List<ProviderResolver>>((ref) {
  final configured = const ConfiguredResolverCatalog().load();

  final providers = <ProviderResolver>[
    for (final config in configured) ConfiguredResolverProvider(config),
    ref.read(nuvioPluginProviderResolverProvider),
    StremioProviderResolver(
      resolver: ref.read(stremioSourceResolverProvider),
      animeMapping: ref.read(animeIdMappingServiceProvider),
    ),
    HttpProviderResolver(ref.read(httpSourceResolverProvider)),
    PublicDomainMovieProviderResolver(
      ref.read(publicDomainMovieResolverProvider),
    ),
  ];

  providers.sort((a, b) => a.priority.compareTo(b.priority));
  return List<ProviderResolver>.unmodifiable(providers);
});
