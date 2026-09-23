import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../addons/stremio_addon_repository.dart';
import '../sources/http_source_repository.dart';
import '../plugins/nuvio_plugin_repository.dart';
import 'configured_resolver_catalog.dart';

class ResolverStatus {
  final int buildResolvers;
  final int localHttpSources;
  final int addons;
  final int builtInResolvers;
  final int nuvioPlugins;

  const ResolverStatus({
    required this.buildResolvers,
    required this.localHttpSources,
    required this.addons,
    required this.builtInResolvers,
    required this.nuvioPlugins,
  });

  int get totalRoutes =>
      buildResolvers + localHttpSources + addons + builtInResolvers + nuvioPlugins;

  int get externalRoutes =>
      buildResolvers + localHttpSources + addons + nuvioPlugins;
}

final resolverStatusProvider = FutureProvider.autoDispose<ResolverStatus>((ref) async {
  final buildResolvers = const ConfiguredResolverCatalog().load().length;
  final http = await ref.read(httpSourceRepositoryProvider).load();
  final addons = await ref.read(stremioAddonRepositoryProvider).load();
  final nuvio = await ref.read(nuvioPluginRepositoryProvider).load();

  return ResolverStatus(
    buildResolvers: buildResolvers,
    localHttpSources: http.where((item) => item.enabled).length,
    addons: addons.where((item) => item.enabled).length,
    builtInResolvers: 1,
    nuvioPlugins: nuvio.where((item) => item.enabled).length,
  );
});
