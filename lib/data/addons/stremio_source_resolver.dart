import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/security/media_url_logging.dart';
import '../../domain/models/stremio_addon_config.dart';
import '../../domain/models/stream_candidate.dart';
import '../../domain/services/source_resolver.dart';
import '../debug/debug_log_provider.dart';
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

  Future<List<String>> debugAddonReport({
    required String mediaType,
    required String mediaId,
    String? externalId,
    String? title,
    String? year,
    int? season,
    int? episode,
  }) async {
    final resolvedExternalId = externalId ??
        await _findExternalId(
          mediaType: mediaType,
          title: title,
          year: year,
        );

    final itemId = StremioProtocol.streamId(
      mediaType: mediaType,
      mediaId: mediaId,
      externalId: resolvedExternalId,
      season: season,
      episode: episode,
    );
    if (itemId == null) {
      return const <String>['Diagnóstico: no se pudo construir streamId.'];
    }

    final type = (mediaType == 'tv' || mediaType == 'anime') ? 'series' : 'movie';
    final addons = (await _repository.load()).where((addon) => addon.enabled).toList();
    final lines = <String>[
      'Diagnóstico de reproducción · add-ons activos: ${addons.length}',
    ];

    for (final addon in addons) {
      try {
        final supported = await _supportsAddonType(addon, type);
        if (!supported) {
          lines.add('Addon ${addon.name}: compatible=no');
          continue;
        }

        final streams = await _resolveAddon(
          addon,
          type: type,
          itemId: itemId,
        );
        lines.add('Addon ${addon.name}: ${streams.length} fuentes.');
        for (var index = 0; index < streams.length; index++) {
          lines.add(
            '  URL ${index + 1}/${streams.length}: ${safeMediaUrlForLog(streams[index].uri)}',
          );
        }
      } catch (error, stack) {
        lines.add('Addon ${addon.name}: ERROR ${safePlaybackErrorForLog(error.toString())}');
        lines.add('Stack: ${safePlaybackErrorForLog(stack.toString())}');
      }
    }

    return lines;
  }

  @override
  Future<List<StreamCandidate>> resolve({
    required String mediaType,
    required String mediaId,
    String? externalId,
    String? title,
    String? year,
    int? season,
    int? episode,
  }) async {
    final resolvedExternalId = externalId ??
        await _findExternalId(
          mediaType: mediaType,
          title: title,
          year: year,
        );

    final itemId = StremioProtocol.streamId(
      mediaType: mediaType,
      mediaId: mediaId,
      externalId: resolvedExternalId,
      season: season,
      episode: episode,
    );
    if (itemId == null) return const [];

    final type = (mediaType == 'tv' || mediaType == 'anime')
        ? 'series'
        : 'movie';
    final addons = await _repository.load();
    final enabled = addons.where((addon) => addon.enabled).toList();
    _log(
      'Stremio resolver: ${enabled.length} addons habilitados para $type/$itemId.',
    );

    final support = await Future.wait([
      for (final addon in enabled) _supportsAddonType(addon, type),
    ]);
    final compatible = <StremioAddonConfig>[
      for (var i = 0; i < enabled.length; i++)
        if (support[i]) enabled[i],
    ];
    _log('Stremio resolver: ${compatible.length} addons compatibles.');

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
    } catch (error, stackTrace) {
      _logError('Stremio manifest ${addon.name}', error, stackTrace);
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
    final streamUri = StremioProtocol.streamUri(
      addon: addon,
      type: type,
      itemId: itemId,
    );
    _log('Stremio addon ${addon.name} GET -> ${safeMediaUrlForLog(streamUri)}');

    try {
      final response = await _dio.getUri<Object?>(
        streamUri,
        options: Options(responseType: ResponseType.json),
      );

      final candidates = StremioProtocol.parseStreams(
        addon: addon,
        raw: response.data,
      );
      _log('Stremio addon ${addon.name}: ${candidates.length} URLs.');
      for (var index = 0; index < candidates.length; index++) {
        _log(
          'Stremio addon ${addon.name} URL ${index + 1}/${candidates.length} '
          '-> ${safeMediaUrlForLog(candidates[index].uri)}',
        );
      }
      return candidates;
    } catch (error, stackTrace) {
      _logError('Stremio addon ${addon.name}', error, stackTrace);
      return const [];
    }
  }

  Future<String?> _findExternalId({
    required String mediaType,
    required String? title,
    String? year,
  }) async {
    if (title == null || title.trim().isEmpty) return null;
    if (mediaType != 'movie' && mediaType != 'tv' && mediaType != 'anime') {
      return null;
    }

    final resource = mediaType == 'movie' ? 'movie' : 'series';
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

      return exactCinemetaId(
        metas: metas,
        title: title,
        year: year,
      );
    } catch (error, stackTrace) {
      _logError('Stremio Cinemeta mapping', error, stackTrace);
      return null;
    }
  }

  /// Never take Cinemeta's first search result when a title doesn't match:
  /// an unrelated film or remake must not be sent to our player.
  @visibleForTesting
  static String? exactCinemetaId({
    required List metas,
    required String title,
    String? year,
  }) {
    final requestedTitle = title.trim().toLowerCase();
    if (requestedTitle.isEmpty) return null;
    final requestedYear = year?.trim() ?? '';
    final ids = <String>{};

    for (final entry in metas) {
      if (entry is! Map) continue;
      final candidateTitle = entry['name']?.toString().trim().toLowerCase();
      if (candidateTitle != requestedTitle) continue;

      final rawId = entry['imdb_id']?.toString().trim() ??
          entry['id']?.toString().trim();
      if (rawId == null || !RegExp(r'^tt[0-9]{5,10}
    debugPrint(message);
    addDebugLog(message);
  }

  void _logError(String scope, Object error, StackTrace stackTrace) {
    final errorLog = '$scope ERROR ${error.runtimeType}: '
        '${safePlaybackErrorForLog(error.toString())}';
    final stackLog = '$scope STACK: ${safePlaybackErrorForLog(stackTrace.toString())}';
    debugPrint(errorLog);
    debugPrint(stackLog);
    addDebugLog(errorLog);
    addDebugLog(stackLog);
  }

  String? _text(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}
).hasMatch(rawId)) {
        continue;
      }

      if (requestedYear.isNotEmpty) {
        final release = (entry['year'] ?? entry['releaseInfo'])?.toString() ?? '';
        final match = RegExp(r'(?:19|20)[0-9]{2}').firstMatch(release);
        if (match == null || match.group(0) != requestedYear) continue;
      }

      ids.add(rawId);
    }

    return ids.length == 1 ? ids.single : null;
  }

  void _log(String message) {
    debugPrint(message);
    addDebugLog(message);
  }

  void _logError(String scope, Object error, StackTrace stackTrace) {
    final errorLog = '$scope ERROR ${error.runtimeType}: '
        '${safePlaybackErrorForLog(error.toString())}';
    final stackLog = '$scope STACK: ${safePlaybackErrorForLog(stackTrace.toString())}';
    debugPrint(errorLog);
    debugPrint(stackLog);
    addDebugLog(errorLog);
    addDebugLog(stackLog);
  }

  String? _text(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}
