import 'package:dio/dio.dart';

enum PotvUpdateChannel { stable, beta }

extension PotvUpdateChannelLabel on PotvUpdateChannel {
  String get label => this == PotvUpdateChannel.stable ? 'Estable' : 'Beta';
}

class PotvInstalledVersion {
  final String name;
  final int code;

  const PotvInstalledVersion({required this.name, required this.code});
}

class PotvUpdateRelease {
  final String tag;
  final String notes;
  final DateTime? publishedAt;
  final String versionName;
  final int versionCode;
  final bool prerelease;
  final Uri apkUrl;
  final int size;
  final String sha256Hex;

  const PotvUpdateRelease({
    required this.tag,
    required this.notes,
    required this.publishedAt,
    required this.versionName,
    required this.versionCode,
    required this.prerelease,
    required this.apkUrl,
    required this.size,
    required this.sha256Hex,
  });

  static final _tag = RegExp(
    r'^v(\d+)\.(\d+)\.(\d+)(-beta\.\d+)?$',
  );
  static final _code = RegExp(
    r'^POTV-Version-Code:\s*(\d+)\s*
  );
  static final _digest = RegExp(r'^sha256:([a-fA-F0-9]{64})$');

  /// Only accept official GitHub Release metadata. A SHA-256 digest and
  /// monotonically increasing Android versionCode are mandatory.
  static PotvUpdateRelease? fromGithub(Object? raw) {
    if (raw is! Map) return null;
    if (raw['draft'] == true) return null;
    final tag = raw['tag_name'];
    if (tag is! String || !_tag.hasMatch(tag)) return null;
    final prerelease = raw['prerelease'] == true;
    if ((tag.contains('-beta.') && !prerelease) ||
        (!tag.contains('-beta.') && prerelease)) {
      return null;
    }
    final notes = (raw['body'] is String ? raw['body'] as String : '');
    final versionCode = int.tryParse(_code.firstMatch(notes)?.group(1) ?? '');
    if (versionCode == null || versionCode <= 0) return null;
    final assets = raw['assets'];
    if (assets is! List) return null;
    for (final entry in assets) {
      if (entry is! Map) continue;
      final name = entry['name'];
      final url = entry['browser_download_url'];
      final digest = entry['digest'];
      final size = entry['size'];
      if (name is! String ||
          !RegExp(r'^POTV-v\d+\.\d+\.\d+(?:-beta\.\d+)?\.apk$')
              .hasMatch(name) ||
          name != 'POTV-$tag.apk' ||
          url is! String ||
          digest is! String ||
          size is! int ||
          size <= 0 ||
          size > 450 * 1024 * 1024) {
        continue;
      }
      final uri = Uri.tryParse(url);
      final validDigest = _digest.firstMatch(digest);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host != 'github.com' ||
          uri.userInfo.isNotEmpty ||
          uri.query.isNotEmpty ||
          uri.fragment.isNotEmpty ||
          uri.path !=
              '/ricardoaldape/POTV/releases/download/$tag/$name' ||
          validDigest == null) {
        continue;
      }
      return PotvUpdateRelease(
        tag: tag,
        notes: notes.replaceAll(_code, '').trim(),
        publishedAt: DateTime.tryParse(
          raw['published_at'] is String ? raw['published_at'] as String : '',
        ),
        versionName: tag.substring(1),
        versionCode: versionCode,
        prerelease: prerelease,
        apkUrl: uri,
        size: size,
        sha256Hex: validDigest.group(1)!.toLowerCase(),
      );
    }
    return null;
  }
}

class PotvUpdateCatalog {
  final Dio dio;

  PotvUpdateCatalog(this.dio);

  static const _uri =
      'https://api.github.com/repos/ricardoaldape/POTV/releases?per_page=30';

  Future<PotvUpdateRelease?> latest({
    required PotvUpdateChannel channel,
    required int installedCode,
  }) async {
    final response = await dio.get<List<dynamic>>(
      _uri,
      options: Options(
        responseType: ResponseType.json,
        headers: {
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 12),
      ),
    );
    final candidates = <PotvUpdateRelease>[];
    for (final release in response.data ?? const []) {
      final item = PotvUpdateRelease.fromGithub(release);
      if (item == null || item.versionCode <= installedCode) continue;
      if (channel == PotvUpdateChannel.stable && item.prerelease) continue;
      candidates.add(item);
    }
    candidates.sort((a, b) => b.versionCode.compareTo(a.versionCode));
    return candidates.isEmpty ? null : candidates.first;
  }
}
,
    multiLine: true,
  );
  static final _digest = RegExp(r'^sha256:([a-fA-F0-9]{64})$');

  /// Only accept official GitHub Release metadata. A SHA-256 digest and
  /// monotonically increasing Android versionCode are mandatory.
  static PotvUpdateRelease? fromGithub(Object? raw) {
    if (raw is! Map) return null;
    if (raw['draft'] == true) return null;
    final tag = raw['tag_name'];
    if (tag is! String || !_tag.hasMatch(tag)) return null;
    final prerelease = raw['prerelease'] == true;
    if ((tag.contains('-beta.') && !prerelease) ||
        (!tag.contains('-beta.') && prerelease)) {
      return null;
    }
    final notes = (raw['body'] is String ? raw['body'] as String : '');
    final versionCode = int.tryParse(_code.firstMatch(notes)?.group(1) ?? '');
    if (versionCode == null || versionCode <= 0) return null;
    final assets = raw['assets'];
    if (assets is! List) return null;
    for (final entry in assets) {
      if (entry is! Map) continue;
      final name = entry['name'];
      final url = entry['browser_download_url'];
      final digest = entry['digest'];
      final size = entry['size'];
      if (name is! String ||
          !RegExp(r'^POTV-v\d+\.\d+\.\d+(?:-beta\.\d+)?\.apk$')
              .hasMatch(name) ||
          name != 'POTV-$tag.apk' ||
          url is! String ||
          digest is! String ||
          size is! int ||
          size <= 0 ||
          size > 450 * 1024 * 1024) {
        continue;
      }
      final uri = Uri.tryParse(url);
      final validDigest = _digest.firstMatch(digest);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host != 'github.com' ||
          uri.userInfo.isNotEmpty ||
          uri.query.isNotEmpty ||
          uri.fragment.isNotEmpty ||
          uri.path !=
              '/ricardoaldape/POTV/releases/download/$tag/$name' ||
          validDigest == null) {
        continue;
      }
      return PotvUpdateRelease(
        tag: tag,
        notes: notes.replaceAll(_code, '').trim(),
        publishedAt: DateTime.tryParse(
          raw['published_at'] is String ? raw['published_at'] as String : '',
        ),
        versionName: tag.substring(1),
        versionCode: versionCode,
        prerelease: prerelease,
        apkUrl: uri,
        size: size,
        sha256Hex: validDigest.group(1)!.toLowerCase(),
      );
    }
    return null;
  }
}

class PotvUpdateCatalog {
  final Dio dio;

  PotvUpdateCatalog(this.dio);

  static const _uri =
      'https://api.github.com/repos/ricardoaldape/POTV/releases?per_page=30';

  Future<PotvUpdateRelease?> latest({
    required PotvUpdateChannel channel,
    required int installedCode,
  }) async {
    final response = await dio.get<List<dynamic>>(
      _uri,
      options: Options(
        responseType: ResponseType.json,
        headers: {
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 12),
      ),
    );
    final candidates = <PotvUpdateRelease>[];
    for (final release in response.data ?? const []) {
      final item = PotvUpdateRelease.fromGithub(release);
      if (item == null || item.versionCode <= installedCode) continue;
      if (channel == PotvUpdateChannel.stable && item.prerelease) continue;
      candidates.add(item);
    }
    candidates.sort((a, b) => b.versionCode.compareTo(a.versionCode));
    return candidates.isEmpty ? null : candidates.first;
  }
}
