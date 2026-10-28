import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../accounts/potv_content_auth_headers.dart';
import '../../providers/user_providers.dart';
import '../../domain/models/partner_content_snapshot.dart';
import '../../domain/models/media_item.dart';

final partnerContentRepositoryProvider = Provider<PartnerContentRepository>((
  ref,
) {
  ref.watch(userAccountProvider);
  return PartnerContentRepository(
    Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 7),
        receiveTimeout: const Duration(seconds: 12),
      ),
    ),
    endpoint: Uri.tryParse(AppConfig.partnerCatalogUrl.trim()),
  );
});

final partnerContentProvider = FutureProvider<PartnerContentSnapshot>((
  ref,
) async {
  // Preserve the two-minute in-memory snapshot across provider invalidations.
  return ref.watch(partnerContentRepositoryProvider).load();
});

/// A bounded metadata page; never contains upstream stream URLs or credentials.
class PartnerMediaPage {
  final MediaType type;
  final String revision;
  final int total;
  final int offset;
  final int limit;
  final bool hasMore;
  final List<MediaItem> items;

  const PartnerMediaPage({
    required this.type,
    required this.revision,
    required this.total,
    required this.offset,
    required this.limit,
    required this.hasMore,
    required this.items,
  });
}

/// Dynamic HTTPS content snapshot, refreshed without installing a new APK.
/// Entitlements and any confidential partner access tokens belong in a secure
/// POTV gateway, never in a Dart define or within the app binary.
class PartnerContentRepository {
  final Dio dio;
  final Uri? endpoint;
  final Duration cacheTtl;
  PartnerContentSnapshot? _snapshot;
  DateTime? _validatedAt;
  String? _etag;

  PartnerContentRepository(
    this.dio, {
    required this.endpoint,
    this.cacheTtl = const Duration(minutes: 2),
  });

  bool get configured =>
      endpoint != null &&
      endpoint!.scheme == 'https' &&
      endpoint!.host.isNotEmpty &&
      endpoint!.userInfo.isEmpty;

  /// Fetch VOD pages beyond the small initial catalog, only through POTV's
  /// authenticated first-party gateway. The account token is never forwarded
  /// to a partner host and authorization failures are not silently cached.
  Future<PartnerMediaPage> loadMediaPage(
    MediaType type, {
    int offset = 0,
    int limit = 200,
  }) async {
    if (!PotvContentAuthHeaders.isFirstPartyGateway(endpoint)) {
      throw StateError('Private media API unavailable');
    }
    if (offset < 0 || offset > 100000 || limit < 1 || limit > 500) {
      throw RangeError('Invalid media page');
    }
    final kind = switch (type) {
      MediaType.movie => 'movies',
      MediaType.tv => 'series',
      MediaType.anime => 'anime',
    };
    final uri = endpoint!.replace(
      path: '/api/v1/content/media',
      queryParameters: {
        'kind': kind,
        'offset': '$offset',
        'limit': '$limit',
      },
      fragment: '',
    );
    final response = await dio.getUri<Object?>(
      uri,
      options: Options(
        responseType: ResponseType.json,
        validateStatus: (status) => status == 200,
        headers: {
          'Accept': 'application/json',
          ...await PotvContentAuthHeaders.forEndpoint(uri),
        },
      ),
    );
    if (response.data is! Map) {
      throw const FormatException('Invalid media page response');
    }
    final document = Map<String, dynamic>.from(response.data as Map);
    if (document['ok'] != true || document['data'] is! Map) {
      throw const FormatException('Invalid media page envelope');
    }
    final data = Map<String, dynamic>.from(document['data'] as Map);
    if (data['kind'] != kind || data['items'] is! List ||
        data['total'] is! int || data['total'] < 0 ||
        data['offset'] != offset || data['limit'] != limit ||
        data['has_more'] is! bool) {
      throw const FormatException('Invalid media page metadata');
    }
    final parsed = PartnerContentSnapshot.parse({
      'data': {kind: data['items']},
    }).forType(type);
    return PartnerMediaPage(
      type: type,
      revision: data['revision']?.toString() ?? '',
      total: data['total'] as int,
      offset: offset,
      limit: limit,
      hasMore: data['has_more'] as bool,
      items: parsed,
    );
  }

  Future<PartnerContentSnapshot> load({bool forceRefresh = false}) async {
    if (!configured) return _snapshot ?? PartnerContentSnapshot.empty();
    final now = DateTime.now();
    if (!forceRefresh &&
        _snapshot != null &&
        _validatedAt != null &&
        now.difference(_validatedAt!) < cacheTtl) {
      return _snapshot!;
    }
    try {
      final response = await dio.getUri<Object?>(
        endpoint!,
        options: Options(
          responseType: ResponseType.json,
          validateStatus: (code) => code == 200 || code == 304,
          headers: {
            'Accept': 'application/json',
            if (_etag != null) 'If-None-Match': _etag!,
            ...await PotvContentAuthHeaders.forEndpoint(endpoint),
          },
        ),
      );
      if (response.statusCode == 304 && _snapshot != null) {
        _validatedAt = now;
        return _snapshot!;
      }
      if (response.statusCode != 200) {
        throw StateError('Unexpected catalog HTTP status');
      }
      final parsed = PartnerContentSnapshot.parse(
        response.data,
        fetchedAt: now,
      );
      // An empty response is a valid catalog revision. Do not accidentally
      // retain removed/expired channels forever.
      _snapshot = parsed;
      _etag = response.headers.value('etag');
      _validatedAt = now;
      return parsed;
    } on Object {
      // Keep an in-memory last-known catalog for transient connectivity loss.
      // Expiring signed stream URLs must still be resolved before playback.
      return _snapshot ?? PartnerContentSnapshot.empty();
    }
  }
}
