import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potv/data/updates/potv_update_catalog.dart';
import 'package:potv/data/updates/potv_update_center.dart';

PotvUpdateRelease _release(List<int> bytes) => PotvUpdateRelease(
      tag: 'v0.8.0',
      notes: '',
      publishedAt: null,
      versionName: '0.8.0',
      versionCode: 13,
      prerelease: false,
      apkUrl: Uri.parse(
        'https://github.com/ricardoaldape/POTV/releases/download/'
        'v0.8.0/POTV-v0.8.0.apk',
      ),
      size: bytes.length,
      sha256Hex: sha256.convert(bytes).toString(),
    );

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('potv-ota-');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('accepts exactly matching file bytes and checksum', () async {
    final bytes = List<int>.generate(90 * 1024, (index) => index % 251);
    final file = File('${temp.path}/verified.apk');
    await file.writeAsBytes(bytes);
    final release = _release(bytes);
    expect(await verifyPotvApk(file, release), isTrue);
  });

  test('rejects tampered APK with identical length', () async {
    final bytes = <int>[1, 2, 3, 4, 5, 6];
    final file = File('${temp.path}/tampered.apk');
    await file.writeAsBytes([1, 2, 3, 4, 5, 7]);
    expect(await verifyPotvApk(file, _release(bytes)), isFalse);
  });

  test('rejects incomplete APK and missing file', () async {
    final bytes = <int>[1, 2, 3, 4, 5, 6];
    final file = File('${temp.path}/incomplete.apk');
    expect(await verifyPotvApk(file, _release(bytes)), isFalse);
    await file.writeAsBytes([1, 2, 3]);
    expect(await verifyPotvApk(file, _release(bytes)), isFalse);
  });
}
