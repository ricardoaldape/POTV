import 'dart:convert';

import '../../core/config/app_config.dart';
import '../../domain/resolution/resolver_endpoint_config.dart';

class ConfiguredResolverCatalog {
  const ConfiguredResolverCatalog();

  List<ResolverEndpointConfig> load() {
    final raw = AppConfig.resolverEndpointsJson.trim();
    if (raw.isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];

      final result = <ResolverEndpointConfig>[];
      for (final value in decoded) {
        if (value is! Map) continue;
        try {
          result.add(
            ResolverEndpointConfig.fromJson(
              value.map(
                (key, value) => MapEntry(key.toString(), value),
              ),
            ),
          );
        } on FormatException {
          continue;
        }
      }

      result.sort((a, b) => a.priority.compareTo(b.priority));
      return List<ResolverEndpointConfig>.unmodifiable(result);
    } on FormatException {
      return const [];
    }
  }
}
