import 'dart:async';
import 'package:http/http.dart' as http;
import '../debug/debug_log_provider.dart';

/// Scraper de AnimeFLV (animeflv.or.at)
class AnimeFlvService {
  static const _baseUrl = 'https://animeflv.or.at';
  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
  static const _timeout = Duration(seconds: 15);

  static Future<List<Map<String, String>>> search(String title) async {
    addDebugLog('AnimeFLV: buscando "$title"');
    final url = '$_baseUrl/?s=${Uri.encodeComponent(title)}';
    try {
      final res = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': _userAgent},
      ).timeout(_timeout);
      if (res.statusCode != 200) {
        addDebugLog('AnimeFLV: HTTP ${res.statusCode}');
        return [];
      }
      final html = res.body;
      addDebugLog('AnimeFLV: ${html.length} chars recibidos');

      final results = <Map<String, String>>[];
      final articleRe = RegExp(
        r'<article[^>]*>(.*?)</article>',
        dotAll: true,
        caseSensitive: false,
      );
      for (final m in articleRe.allMatches(html)) {
        final block = m.group(1) ?? '';
        final href = RegExp(r'<a[^>]+href="([^"]+)"').firstMatch(block);
        final img = RegExp(r'<img[^>]+src="([^"]+)"').firstMatch(block);
        final titleMatch = RegExp(r'<h[23][^>]*>([^<]+)</h[23]>').firstMatch(block);
        if (href == null) continue;
        final hrefUrl = href.group(1)!;
        if (!hrefUrl.contains('/anime/')) continue;
        final slugMatch = RegExp(r'/anime/([^/]+)/?').firstMatch(hrefUrl);
        if (slugMatch == null) continue;
        results.add({
          'title': titleMatch?.group(1)?.trim() ?? 'Sin título',
          'slug': slugMatch.group(1)!,
          'cover': img?.group(1) ?? '',
          'url': hrefUrl,
        });
        if (results.length >= 20) break;
      }
      addDebugLog('AnimeFLV: encontrados ${results.length} resultados');
      if (results.isEmpty) {
        final preview = html.length > 500 ? html.substring(0, 500) : html;
        addDebugLog('AnimeFLV HTML (500): $preview');
      }
      return results;
    } catch (e) {
      addDebugLog('AnimeFLV: excepción $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>?> getDetails(String slug) async {
    addDebugLog('AnimeFLV: getDetails "$slug"');
    final url = '$_baseUrl/anime/$slug/';
    try {
      final res = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': _userAgent},
      ).timeout(_timeout);
      if (res.statusCode != 200) {
        addDebugLog('AnimeFLV: HTTP ${res.statusCode} en detalle');
        return null;
      }
      final html = res.body;
      addDebugLog('AnimeFLV: detalle ${html.length} chars');

      final titleMatch = RegExp(r'<h1[^>]*>([^<]+)</h1>').firstMatch(html);
      final coverMatch = RegExp(
        r'<div[^>]*class="[^"]*AnimeCover[^"]*"[^>]*>.*?<img[^>]+src="([^"]+)"',
        dotAll: true,
      ).firstMatch(html);
      final synopsisMatch = RegExp(
        r'<div[^>]*class="[^"]*Description[^"]*"[^>]*>(.*?)</div>',
        dotAll: true,
      ).firstMatch(html);

      final episodes = <Map<String, String>>[];
      final epBlock = RegExp(
        r'<ul[^>]*class="[^"]*ListEpisodios[^"]*"[^>]*>(.*?)</ul>',
        dotAll: true,
      ).firstMatch(html);
      if (epBlock != null) {
        final epRe = RegExp(r'<a[^>]+href="([^"]+)"[^>]*>([^<]*)</a>');
        for (final m in epRe.allMatches(epBlock.group(1)!)) {
          final epUrl = m.group(1)!;
          final epText = m.group(2)!.trim();
          if (epUrl.isEmpty) continue;
          episodes.add({
            'name': epText.isEmpty ? 'Episodio' : epText,
            'url': epUrl,
          });
        }
      }
      addDebugLog('AnimeFLV: ${episodes.length} episodios encontrados');
      return {
        'title': titleMatch?.group(1)?.trim() ?? slug,
        'cover': coverMatch?.group(1) ?? '',
        'synopsis': synopsisMatch?.group(1)?.replaceAll(RegExp(r'<[^>]+>'), '').trim() ?? '',
        'episodes': episodes,
      };
    } catch (e) {
      addDebugLog('AnimeFLV: excepción en detalle $e');
      return null;
    }
  }

  static Future<List<Map<String, String>>> getServers(String episodeUrl) async {
    addDebugLog('AnimeFLV: getServers "$episodeUrl"');
    try {
      final res = await http.get(
        Uri.parse(episodeUrl),
        headers: {
          'User-Agent': _userAgent,
          'Referer': '$_baseUrl/',
        },
      ).timeout(_timeout);
      if (res.statusCode != 200) {
        addDebugLog('AnimeFLV: HTTP ${res.statusCode} en episodio');
        return [];
      }
      final html = res.body;
      addDebugLog('AnimeFLV: episodio ${html.length} chars');
      final servers = <Map<String, String>>[];
      final liRe = RegExp(r'<li[^>]*>(.*?)</li>', dotAll: true);
      for (final m in liRe.allMatches(html)) {
        final block = m.group(1)!;
        final dataVideo = RegExp(r'data-video="([^"]+)"').firstMatch(block);
        final href = RegExp(r'href="([^"]+)"').firstMatch(block);
        final nameMatch = RegExp(r'>([^<]+)</a>').firstMatch(block);
        final url = dataVideo?.group(1) ?? href?.group(1) ?? '';
        if (url.isEmpty) continue;
        if (!url.startsWith('http')) continue;
        if (url.contains('facebook') ||
            url.contains('twitter') ||
            url.contains('whatsapp') ||
            url.contains('/anime/') ||
            url.contains('/episodio')) {
          continue;
        }
        servers.add({
          'server': nameMatch?.group(1)?.trim() ?? 'Servidor',
          'url': url,
        });
        if (servers.length >= 15) break;
      }
      addDebugLog('AnimeFLV: ${servers.length} servidores encontrados');
      if (servers.isEmpty) {
        final preview = html.length > 600 ? html.substring(0, 600) : html;
        addDebugLog('AnimeFLV HTML ep (600): $preview');
      }
      return servers;
    } catch (e) {
      addDebugLog('AnimeFLV: excepción en servidores $e');
      return [];
    }
  }

  static Future<void> runSmokeTest() async {
    addDebugLog('=== AnimeFLV Smoke Test INICIO ===');
    final results = await search('attack on titan');
    addDebugLog('Smoke: búsqueda devolvió ${results.length} resultados');
    if (results.isNotEmpty) {
      addDebugLog('Smoke: primer resultado = ${results.first}');
      final slug = results.first['slug'] ?? '';
      if (slug.isNotEmpty) {
        final details = await getDetails(slug);
        final episodes = details?['episodes'] as List? ?? [];
        addDebugLog('Smoke: episodios = ${episodes.length}');
        if (episodes.isNotEmpty) {
          final epUrl = (episodes.first as Map)['url'] as String? ?? '';
          final servers = await getServers(epUrl);
          addDebugLog('Smoke: servidores = ${servers.length}');
          if (servers.isNotEmpty) {
            addDebugLog('Smoke: primer servidor = ${servers.first}');
          }
        }
      }
    }
    addDebugLog('=== AnimeFLV Smoke Test FIN ===');
  }
}