import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../addons/stremio_addon_repository.dart';
import '../sources/http_source_repository.dart';
import 'configured_resolver_catalog.dart';

class ResolverStatus {
  final int buildResolvers;
  final int localHttpSources;
  final int addons;
  final int builtInResolvers;

  const ResolverStatus({
    required this.buildResolvers,
    required this.localHttpSources,
    required this.addons,
    required this.builtInResolvers,
  });

  int get totalRoutes =>
      buildResolvers + localHttpSources + addons + builtInResolvers;
}

final resolverStatusProvider = FutureProvider.autoDispose<ResolverStatus>((ref) async {
  final buildResolvers = const ConfiguredResolverCatalog().load().length;
  final http = await ref.read(httpSourceRepositoryProvider).load();
  final addons = await ref.read(stremioAddonRepositoryProvider).load();

  return ResolverStatus(
    buildResolvers: buildResolvers,
    localHttpSources: http.where((item) => item.enabled).length,
    addons: addons.where((item) => item.enabled).length,
    builtInResolvers: 2,
  );
});
