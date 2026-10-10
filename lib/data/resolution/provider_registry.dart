import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../domain/resolution/resolver_endpoint_config.dart';
import '../../domain/resolution/provider_resolver.dart';
import '../addons/stremio_source_resolver.dart';
import '../anime/anime_id_mapping_service.dart';
// import '../extractors/embed69_extractor.dart';
import '../plugins/nuvio_plugin_provider.dart';
import '../sources/http_source_resolver.dart';
import '../sources/public_domain_movie_resolver.dart';
import 'configured_resolver_catalog.dart';
import 'configured_resolver_provider.dart';
import 'partner_api_source_resolver.dart';
import 'provider_adapters.dart';
import 'lolplus_adapters.dart';

final providerRegistryProvider = Provider<List<ProviderResolver>>((ref) {
  final configured = const ConfiguredResolverCatalog().load();

  // A whitelabel partner source endpoint is called on each title resolution.
  // Its backend may add, remove, reprioritize or repair servers independently
  // of the installed POTV APK.
  final partnerApi = Uri.tryParse(AppConfig.partnerApiBaseUrl.trim());
  final partnerUrl = Uri.tryParse(AppConfig.partnerSourcesUrl.trim());
  final partnerEnabled = partnerUrl != null &&
      partnerUrl.scheme == 'https' &&
      partnerUrl.host.isNotEmpty &&
      partnerUrl.userInfo.isEmpty;

  final providers = <ProviderResolver>[
    if (partnerApi != null && partnerApi.scheme == 'https' &&
        partnerApi.host.isNotEmpty && partnerApi.userInfo.isEmpty)
      PartnerApiSourceResolver(
        baseUrl: partnerApi,
        animeMapping: ref.read(animeIdMappingServiceProvider),
      ),
    if (partnerEnabled)
      ConfiguredResolverProvider(ResolverEndpointConfig(
        id: 'potv_partner_sources',
        name: 'POTV',
        endpoint: partnerUrl,
        mediaTypes: const {'movie', 'tv', 'anime'},
        priority: 1,
      )),
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
