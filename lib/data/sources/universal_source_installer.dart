import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../addons/stremio_addon_client.dart';
import '../addons/stremio_addon_repository.dart';
import '../live_tv/live_tv_repository.dart';
import '../plugins/nuvio_plugin_repository.dart';

final universalSourceInstallerProvider = Provider<UniversalSourceInstaller>((ref) {
  return UniversalSourceInstaller(
    dio: Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 15),
      headers: const {'Accept': 'application/json,text/plain,*/*'},
    )),
    stremioClient: ref.read(stremioAddonClientProvider),
    stremioRepository: ref.read(stremioAddonRepositoryProvider),
    nuvioRepository: ref.read(nuvioPluginRepositoryProvider),
    liveTvRepository: ref.read(liveTvRepositoryProvider),
  );
});

enum UniversalSourceKind { stremio, nuvioPlugins, m3u, cloudStreamRepository }

class UniversalSourceInstallResult {
  final UniversalSourceKind kind;
  final String name;
  final String message;
  final int added;
  final bool active;
  const UniversalSourceInstallResult({
    required this.kind,
    required this.name,
    required this.message,
    this.added = 1,
    this.active = true,
  });
}

class UniversalSourceInstaller {
  final Dio dio;
  final StremioAddonClient stremioClient;
  final StremioAddonRepository stremioRepository;
  final NuvioPluginRepository nuvioRepository;
  final LiveTvRepository liveTvRepository;

  UniversalSourceInstaller({
    required this.dio,
    required this.stremioClient,
    required this.stremioRepository,
    required this.nuvioRepository,
    required this.liveTvRepository,
  });

  Future<UniversalSourceInstallResult> install(String input) async {
    final uri = _normalize(input);
    Object? lastError;
    for (final candidate in _candidates(uri)) {
      try {
        final response = await dio.getUri<String>(candidate, options: Options(responseType: ResponseType.plain));
        final body = response.data?.trim() ?? '';
        if (body.isEmpty) continue;
        final result = await _installDetected(candidate, body);
        if (result != null) return result;
      } catch (error) {
        lastError = error;
      }
    }
    if (lastError != null) {
      throw FormatException('No pudimos reconocer una fuente compatible en esa URL.');
    }
    throw const FormatException('La URL no corresponde a una fuente compatible con POTV.');
  }

  Future<UniversalSourceInstallResult?> _installDetected(Uri uri, String body) async {
    if (body.startsWith('#EXTM3U') && body.contains('#EXTINF')) {
      await liveTvRepository.saveSource(uri.toString());
      return const UniversalSourceInstallResult(
        kind: UniversalSourceKind.m3u,
        name: 'Lista de TV',
        message: 'Lista M3U añadida. POTV cargará sus canales automáticamente.',
      );
    }

    dynamic decoded;
    try { decoded = jsonDecode(body); } catch (_) { return null; }
    if (decoded is! Map<String, dynamic>) return null;

    if (_isStremioManifest(decoded)) {
      final manifest = await stremioClient.inspect(uri);
      final existing = await stremioRepository.load();
      final duplicate = existing.any((item) => item.manifestUri.toString() == manifest.manifestUri.toString());
      if (!duplicate) {
        await stremioRepository.add(name: manifest.name, manifestUri: manifest.manifestUri);
      }
      return UniversalSourceInstallResult(
        kind: UniversalSourceKind.stremio,
        name: manifest.name,
        added: duplicate ? 0 : 1,
        message: duplicate ? '${manifest.name} ya estaba instalado.' : '${manifest.name} añadido y listo para usarse automáticamente.',
      );
    }

    if (decoded['scrapers'] is List) {
      final installed = await nuvioRepository.addRepository(uri);
      return UniversalSourceInstallResult(
        kind: UniversalSourceKind.nuvioPlugins,
        name: installed.name,
        added: installed.added,
        message: '${installed.name}: ${installed.added} plugins nuevos disponibles para resolución automática.',
      );
    }

    if (decoded['manifestVersion'] != null && decoded['pluginLists'] is List) {
      return UniversalSourceInstallResult(
        kind: UniversalSourceKind.cloudStreamRepository,
        name: decoded['name']?.toString().trim().isNotEmpty == true ? decoded['name'].toString().trim() : 'Repositorio CloudStream',
        message: 'Repositorio CloudStream detectado. El bridge .cs3 todavía no está activo en este build.',
        added: 0,
        active: false,
      );
    }

    return null;
  }

  bool _isStremioManifest(Map<String, dynamic> raw) {
    if (raw['id'] == null || raw['name'] == null) return false;
    final resources = raw['resources'];
    if (resources is! List) return false;
    return resources.any((value) {
      if (value == 'stream') return true;
      if (value is Map) return value['name'] == 'stream';
      return false;
    });
  }

  Uri _normalize(String input) {
    var value = input.trim();
    if (value.isEmpty) throw const FormatException('Pega una URL.');
    if (!value.contains('://')) value = 'https://$value';
    final uri = Uri.tryParse(value);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) {
      throw const FormatException('La URL no es válida.');
    }
    return uri;
  }

  List<Uri> _candidates(Uri input) {
    final result = <Uri>[input];
    final path = input.path.toLowerCase();

    if (input.host == 'github.com') {
      final segments = input.pathSegments.where((part) => part.isNotEmpty).toList();
      if (segments.length >= 2) {
        final owner = segments[0];
        final repo = segments[1].replaceAll(RegExp(r'\.git$'), '');
        for (final branch in const ['main', 'master', 'builds']) {
          result.add(Uri.parse('https://raw.githubusercontent.com/$owner/$repo/$branch/manifest.json'));
          result.add(Uri.parse('https://raw.githubusercontent.com/$owner/$repo/$branch/repo.json'));
        }
      }
    }

    if (input.host == 'codeberg.org') {
      final segments = input.pathSegments.where((part) => part.isNotEmpty).toList();
      if (segments.length >= 2) {
        final owner = segments[0];
        final repo = segments[1];
        for (final branch in const ['main', 'master', 'builds']) {
          result.add(Uri.parse('https://codeberg.org/$owner/$repo/raw/branch/$branch/manifest.json'));
          result.add(Uri.parse('https://codeberg.org/$owner/$repo/raw/branch/$branch/repo.json'));
        }
      }
    }

    if (!path.endsWith('.json') && !path.endsWith('.m3u') && !path.endsWith('.m3u8')) {
      final base = input.path.endsWith('/') ? input : input.replace(path: '${input.path}/');
      result.add(base.resolve('manifest.json'));
      result.add(base.resolve('repo.json'));
    }
    final seen = <String>{};
    return result.where((uri) => seen.add(uri.toString())).toList(growable: false);
  }
}
