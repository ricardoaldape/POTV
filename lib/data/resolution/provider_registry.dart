import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/resolution/provider_resolver.dart';
import '../addons/stremio_source_resolver.dart';
import '../anime/anime_id_mapping_service.dart';
// import '../extractors/embed69_extractor.dart';
import '../plugins/nuvio_plugin_provider.dart';
import '../sources/http_source_resolver.dart';
import '../sources/public_domain_movie_resolver.dart';
import 'configured_resolver_catalog.dart';
import 'configured_resolver_provider.dart';
import 'provider_adapters.dart';
import 'lolplus_adapters.dart';

final providerRegistryProvider = Provider<List<ProviderResolver>>((ref) {
  final configured = const ConfiguredResolverCatalog().load();

  final providers = <ProviderResolver>[
    for (final config in configured) ConfiguredResolverProvider(config),
    ref.read(nuvioPluginProviderResolverProvider),
    // Embed69ProviderResolver(
    //   extractor: const Embed69Extractor(),
    //   enabled: true,
    // ),
    StremioProviderResolver(
      resolver: ref.read(stremioSourceResolverProvider),
      animeMapping: ref.read(animeIdMappingServiceProvider),
    ),
    CuevanaProviderResolver(animeMapping: ref.read(animeIdMappingServiceProvider)),
    TioPlusProviderResolver(animeMapping: ref.read(animeIdMappingServiceProvider)),
    PelisPlusProviderResolver(animeMapping: ref.read(animeIdMappingServiceProvider)),
    CinecalidadProviderResolver(animeMapping: ref.read(animeIdMappingServiceProvider)),
    CineSrcProviderResolver(animeMapping: ref.read(animeIdMappingServiceProvider)),
    VidSrcProviderResolver(animeMapping: ref.read(animeIdMappingServiceProvider)),
    MultiEmbedProviderResolver(animeMapping: ref.read(animeIdMappingServiceProvider)),
    HackStoreProviderResolver(animeMapping: ref.read(animeIdMappingServiceProvider)),
    UnlimplayProviderResolver(animeMapping: ref.read(animeIdMappingServiceProvider)),
    PoseidonProviderResolver(animeMapping: ref.read(animeIdMappingServiceProvider)),
    PelispediaProviderResolver(animeMapping: ref.read(animeIdMappingServiceProvider)),
    SeriesMetroProviderResolver(animeMapping: ref.read(animeIdMappingServiceProvider)),
    SmartPelisProviderResolver(animeMapping: ref.read(animeIdMappingServiceProvider)),
    Embed69ProviderResolver(animeMapping: ref.read(animeIdMappingServiceProvider)),
    HttpProviderResolver(ref.read(httpSourceResolverProvider)),
    PublicDomainMovieProviderResolver(
      ref.read(publicDomainMovieResolverProvider),
    ),
  ];

  providers.sort((a, b) => a.priority.compareTo(b.priority));
  return List<ProviderResolver>.unmodifiable(providers);
});
