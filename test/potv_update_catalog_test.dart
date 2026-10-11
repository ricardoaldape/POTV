import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potv/data/updates/potv_update_catalog.dart';

const _hash =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

Map<String, Object?> release({
  String tag = 'v0.8.0',
  int code = 13,
  bool? prerelease,
  String digest = 'sha256:$_hash',
  String? url,
  int size = 56000000,
  String? notes,
  bool draft = false,
}) => {
      'tag_name': tag,
      'prerelease': prerelease ?? tag.contains('-beta.'),
      'draft': draft,
      'published_at': '2026-10-11T16:00:00Z',
      'body': '${notes ?? 'Mejoras de rendimiento.'}\nPOTV-Version-Code: $code',
      'assets': [
        {
          'name': 'POTV-$tag.apk',
          'browser_download_url': url ??
              'https://github.com/ricardoaldape/POTV/releases/download/$tag/POTV-$tag.apk',
          'digest': digest,
          'size': size,
        }
      ],
    };

void main() {
  test('accepts official signed metadata for a stable APK', () {
    final item = PotvUpdateRelease.fromGithub(release());
    expect(item, isNotNull);
    expect(item!.versionName, '0.8.0');
    expect(item.versionCode, 13);
    expect(item.sha256Hex, _hash);
    expect(item.size, 56000000);
    expect(item.notes, isNot(contains('POTV-Version-Code:')));
  });

  test('rejects missing SHA, non-official hosts, drafts and malformed tags', () {
    expect(PotvUpdateRelease.fromGithub(release(digest: '')), isNull);
    expect(PotvUpdateRelease.fromGithub(release(
      url: 'https://attacker.example/POTV-v0.8.0.apk',
    )), isNull);
    expect(PotvUpdateRelease.fromGithub(release(draft: true)), isNull);
    expect(PotvUpdateRelease.fromGithub(release(tag: 'v1')), isNull);
    expect(PotvUpdateRelease.fromGithub(release(code: 0)), isNull);
    expect(PotvUpdateRelease.fromGithub(release(size: 470000000)), isNull);
    expect(PotvUpdateRelease.fromGithub(release(
      tag: 'v0.8.0-beta.1',
      prerelease: false,
    )), isNull);
  });

  test('stable ignores beta and cannot downgrade by versionCode', () async {
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      expect(options.uri.host, 'api.github.com');
      handler.resolve(Response<List<dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: [
          release(tag: 'v0.9.0-beta.1', code: 15),
          release(tag: 'v0.8.1', code: 14),
          release(tag: 'v0.8.0', code: 13),
          release(tag: 'v0.7.9', code: 11),
          release(tag: 'v1'), // Legacy metadata without versionCode format.
        ],
      ));
    }));
    final service = PotvUpdateCatalog(dio);
    final stable = await service.latest(
      channel: PotvUpdateChannel.stable, installedCode: 13,
    );
    final beta = await service.latest(
      channel: PotvUpdateChannel.beta, installedCode: 13,
    );
    expect(stable?.versionCode, 14);
    expect(stable?.prerelease, isFalse);
    expect(beta?.versionCode, 15);
    expect(beta?.prerelease, isTrue);
    expect(await service.latest(
      channel: PotvUpdateChannel.stable, installedCode: 20,
    ), isNull);
  });

  test('beta may select a newer stable build over an older beta', () async {
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response<List<dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: [
          release(tag: 'v0.9.0-beta.1', code: 14),
          release(tag: 'v0.8.0', code: 15),
        ],
      ));
    }));
    final result = await PotvUpdateCatalog(dio).latest(
      channel: PotvUpdateChannel.beta, installedCode: 13,
    );
    expect(result?.versionCode, 15);
  });
}
