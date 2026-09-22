import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final stremioAddonClientProvider = Provider<StremioAddonClient>((ref) {
  return StremioAddonClient(
    Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 12),
        headers: const {
          'Accept': 'application/json',
          'User-Agent': 'POTV/0.1 (Android)',
        },
      ),
    ),
  );
});

class StremioManifestInfo {
  final String id;
  final String name;
  final String version;
  final Set<String> resources;
  final Set<String> types;
  final Uri manifestUri;

  const StremioManifestInfo({
    required this.id,
    required this.name,
    required this.version,
    required this.resources,
    required this.types,
    required this.manifestUri,
  });

  bool get supportsStreams => resources.contains('stream');
}

class StremioAddonClient {
  final Dio _dio;

  StremioAddonClient(this._dio);

  Future<StremioManifestInfo> inspect(Uri input) async {
    final manifestUri = normalizeManifestUri(input);

    final response = await _dio.getUri<Object?>(
      manifestUri,
      options: Options(responseType: ResponseType.json),
    );

    final raw = response.data;
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('El manifest del addon no es JSON válido.');
    }

    final id = _text(raw['id']);
    final name = _text(raw['name']);
    final version = _text(raw['version']) ?? '0.0.0';
    if (id == null || name == null) {
      throw const FormatException(
        'El manifest no contiene id y nombre válidos.',
      );
    }

    final resources = <String>{};
    final resourcesRaw = raw['resources'];
    if (resourcesRaw is List) {
      for (final value in resourcesRaw) {
        if (value is String && value.trim().isNotEmpty) {
          resources.add(value.trim());
        } else if (value is Map) {
          final resourceName = _text(value['name']);
          if (resourceName != null) resources.add(resourceName);
        }
      }
    }

    final types = <String>{};
    final typesRaw = raw['types'];
    if (typesRaw is List) {
      for (final value in typesRaw) {
        final type = _text(value);
        if (type != null) types.add(type);
      }
    }

    return StremioManifestInfo(
      id: id,
      name: name,
      version: version,
      resources: resources,
      types: types,
      manifestUri: manifestUri,
    );
  }

  Uri normalizeManifestUri(Uri input) {
    if (input.scheme != 'http' && input.scheme != 'https') {
      throw const FormatException('La URL debe ser HTTP o HTTPS.');
    }

    final path = input.path;
    if (path.endsWith('/manifest.json') || path == 'manifest.json') {
      return input;
    }

    final normalizedPath = path.endsWith('/')
        ? '${path}manifest.json'
        : '$path/manifest.json';

    return input.replace(
      path: normalizedPath,
      query: null,
      fragment: null,
    );
  }

  String? _text(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}
