import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/stremio_addon_config.dart';
import '../../domain/models/stream_candidate.dart';
import '../../domain/services/source_resolver.dart';
import 'stremio_addon_client.dart';
import 'stremio_addon_repository.dart';
import 'stremio_protocol.dart';

final stremioSourceResolverProvider = Provider<StremioSourceResolver>((ref) {
  return StremioSourceResolver(
    ref.read(stremioAddonRepositoryProvider),
    Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 14),
        headers: const {
          'Accept': 'application/json',
          'User-Agent': 'POTV/0.1 (Android)',
        },
      ),
    ),
  );
});

class StremioSourceResolver implements SourceResolver {
  final StremioAddonRepository _repository;
  final Dio _dio;
  final Map<String, StremioManifestInfo?> _manifestCache = {};

  StremioSourceResolver(this._repository, this._dio);

  @override
  Future<List<StreamCandidate>> resolve({
    required String mediaType,
    required String mediaId,
    String? externalId,
    String? title,
    int? season,
    int? episode,
  }) async {
    if (mediaType == 'anime') return const [];

    final resolvedExternalId = externalId ??
        await _findExternalId(
          mediaType: mediaType,
          title: title,
        );

    final itemId = StremioProtocol.streamId(
      mediaType: mediaType,
      mediaId: mediaId,
      externalId: resolvedExternalId,
      season: season,
      episode: episode,
    );
    if (itemId == null) return const [];

    final type = mediaType == 'tv' ? 'series' : 'movie';
    final addons = await _repository.load();
    final enabled = addons.where((addon) => addon.enabled).toList();

    final support = await Future.wait([
      for (final addon in enabled) _supportsAddonType(addon, type),
    ]);
    final compatible = <StremioAddonConfig>[
      for (var i = 0; i < enabled.length; i++)
        if (support[i]) enabled[i],
    ];

    final batches = await Future.wait([
      for (final addon in compatible)
        _resolveAddon(
          addon,
          type: type,
          itemId: itemId,
        ),
    ]);

    return [
      for (final batch in batches) ...batch,
    ];
  }

  Future<bool> _supportsAddonType(
    StremioAddonConfig addon,
    String type,
  ) async {
    if (_manifestCache.containsKey(addon.id)) {
      final cached = _manifestCache[addon.id];
      if (cached == null) return true;
      return cached.supportsStreams &&
          (cached.types.isEmpty || cached.types.contains(type));
    }

    try {
      final client = StremioAddonClient(_dio);
      final manifest = await client.inspect(addon.manifestUri);
      _manifestCache[addon.id] = manifest;
      return manifest.supportsStreams &&
          (manifest.types.isEmpty || manifest.types.contains(type));
    } catch (_) {
      // Some compatible endpoints expose streams but reject manifest probing.
      // Keep them eligible instead of breaking an already configured source.
      _manifestCache[addon.id] = null;
      return true;
    }
  }

  Future<List<StreamCandidate>> _resolveAddon(
    StremioAddonConfig addon, {
    required String type,
    required String itemId,
  }) async {
    try {
      final streamUri = StremioProtocol.streamUri(
        addon: addon,
        type: type,
        itemId: itemId,
      );

      final response = await _dio.getUri<Object?>(
        streamUri,
        options: Options(responseType: ResponseType.json),
      );

      return StremioProtocol.parseStreams(
        addon: addon,
        raw: response.data,
      );
    } on DioException {
      return const [];
    } on FormatException {
      return const [];
    }
  }

  Future<String?> _findExternalId({
    required String mediaType,
    required String? title,
  }) async {
    if (title == null || title.trim().isEmpty) return null;
    if (mediaType != 'movie' && mediaType != 'tv') return null;

    final resource = mediaType == 'tv' ? 'series' : 'movie';
    final encoded = Uri.encodeComponent(title.trim());
    final uri = Uri.parse(
      'https://v3-cinemeta.strem.io/catalog/$resource/top/search=$encoded.json',
    );

    try {
      final response = await _dio.getUri<Object?>(
        uri,
        options: Options(responseType: ResponseType.json),
      );
      final raw = response.data;
      if (raw is! Map<String, dynamic>) return null;
      final metas = raw['metas'];
      if (metas is! List) return null;

      final target = title.trim().toLowerCase();
      Map<String, dynamic>? first;
      for (final value in metas) {
        if (value is! Map<String, dynamic>) continue;
        first ??= value;
        final name = _text(value['name'])?.toLowerCase();
        if (name == target) {
          return _text(value['imdb_id']) ?? _text(value['id']);
        }
      }

      if (first == null) return null;
      return _text(first['imdb_id']) ?? _text(first['id']);
    } on DioException {
      return null;
    }
  }

  String? _text(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}
