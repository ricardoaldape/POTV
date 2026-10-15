import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/playback_session.dart';
import '../addons/stremio_addon_client.dart';
import 'stremio_addon_repository.dart';

final stremioSubtitleServiceProvider = Provider<StremioSubtitleService>((ref) {
  return StremioSubtitleService(
    ref.read(stremioAddonRepositoryProvider),
    Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
      headers: const {'Accept': 'application/json'},
    )),
  );
});

class StremioSubtitle {
  final String id;
  final String language;
  final String label;
  final Uri url;

  const StremioSubtitle({
    required this.id,
    required this.language,
    required this.label,
    required this.url,
  });

  bool get isSpanish {
    final lang = language.toLowerCase().replaceAll('_', '-');
    return lang == 'es' || lang == 'spa' || lang.startsWith('es-') ||
        lang == 'spanish' || lang == 'espanol' || lang == 'español';
  }

  static List<StremioSubtitle> parse(Object? raw) {
    if (raw is! Map || raw['subtitles'] is! List) return const [];
    final result = <StremioSubtitle>[];
    final seen = <String>{};
    for (final item in raw['subtitles'] as List) {
      if (item is! Map) continue;
      final url = Uri.tryParse(item['url']?.toString() ?? '');
      if (url == null || url.scheme != 'https' || url.host.isEmpty ||
          url.userInfo.isNotEmpty) continue;
      final language = item['lang']?.toString().trim() ??
          item['language']?.toString().trim() ?? '';
      final label = item['label']?.toString().trim();
      if (language.isEmpty) continue;
      if (!seen.add(url.toString())) continue;
      result.add(StremioSubtitle(
        id: item['id']?.toString() ?? url.host,
        language: language,
        label: label == null || label.isEmpty ? language : label,
        url: url,
      ));
      if (result.length >= 40) break;
    }
    result.sort((a, b) =>
        (b.isSpanish ? 1 : 0).compareTo(a.isSpanish ? 1 : 0));
    return List.unmodifiable(result);
  }
}

class StremioSubtitleService {
  final StremioAddonRepository repository;
  final Dio dio;

  const StremioSubtitleService(this.repository, this.dio);

  Future<List<StremioSubtitle>> forPlayback(PlaybackContext context) async {
    final externalId = context.externalId;
    if (externalId == null || !RegExp(r'^tt\d+$').hasMatch(externalId)) {
      return const [];
    }
    final type = context.mediaType == 'movie' ? 'movie' : 'series';
    final episodeId = type == 'movie'
        ? externalId
        : '$externalId:${context.season ?? 1}:${context.episode ?? 1}';
    final addons = await repository.load();
    // Catalog-only addons are common in the partner discovery list. A
    // six-addon cap could silently exclude real subtitle providers that
    // appear later (e.g. OpenSubtitles installed after six catalogs).
    // Keep a bounded number of HTTPS probes, then inspect each manifest's
    // declared resources before requesting subtitle files.
    final enabled = addons.where((a) => a.enabled).take(24).toList();
    final batches = await Future.wait([
      for (final addon in enabled)
        () async {
          try {
            final manifest = await StremioAddonClient(dio)
                .inspect(addon.manifestUri);
            if (!manifest.resources.contains('subtitles')) {
              return const <StremioSubtitle>[];
            }
            final uri = addon.manifestUri.resolve(
              'subtitles/$type/${Uri.encodeComponent(episodeId)}.json',
            );
            final response = await dio.getUri<Object?>(
              uri, options: Options(responseType: ResponseType.json),
            );
            return StremioSubtitle.parse(response.data);
          } catch (_) {
            // Subtitles are optional. Do not break or delay video on failure.
            // Never log the authenticated manifest or request URL.
            return const <StremioSubtitle>[];
          }
        }(),
    ]);
    final seen = <String>{};
    return [
      for (final group in batches)
        for (final subtitle in group)
          if (seen.add(subtitle.url.toString())) subtitle,
    ];
  }
}
