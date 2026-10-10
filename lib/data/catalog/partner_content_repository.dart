import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../domain/models/partner_content_snapshot.dart';

final partnerContentRepositoryProvider = Provider<PartnerContentRepository>((ref) {
  return PartnerContentRepository(
    Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 7),
      receiveTimeout: const Duration(seconds: 12),
    )),
    endpoint: Uri.tryParse(AppConfig.partnerCatalogUrl.trim()),
  );
});

final partnerContentProvider = FutureProvider<PartnerContentSnapshot>((ref) async {
  return ref.read(partnerContentRepositoryProvider).load(forceRefresh: true);
});

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

  bool get configured => endpoint != null &&
      endpoint!.scheme == 'https' &&
      endpoint!.host.isNotEmpty &&
      endpoint!.userInfo.isEmpty;

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
