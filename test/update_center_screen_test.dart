import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potv/data/updates/potv_update_catalog.dart';
import 'package:potv/data/updates/potv_update_center.dart';
import 'package:potv/features/updates/update_center_screen.dart';

class _FakeUpdateCenter extends PotvUpdateCenter {
  _FakeUpdateCenter() : super(Dio());
  PotvUpdateChannel active = PotvUpdateChannel.stable;
  @override
  Future<PotvInstalledVersion> installedVersion() async =>
      const PotvInstalledVersion(name: '0.8.0', code: 13);
  @override
  Future<PotvUpdateChannel> selectedChannel() async => active;
  @override
  Future<void> changeChannel(PotvUpdateChannel channel) async {
    active = channel;
  }
  @override
  Future<PotvUpdateRelease?> check({
    required PotvUpdateChannel channel,
    required PotvInstalledVersion installed,
  }) async {
    if (channel == PotvUpdateChannel.stable) return null;
    return PotvUpdateRelease(
      tag: 'v0.9.0-beta.1',
      notes: 'Nuevo Sports Hub y TV en vivo',
      publishedAt: DateTime(2026, 10, 11),
      versionName: '0.9.0-beta.1',
      versionCode: 14,
      prerelease: true,
      apkUrl: Uri.parse(
        'https://github.com/ricardoaldape/POTV/releases/download/'
        'v0.9.0-beta.1/POTV-v0.9.0-beta.1.apk',
      ),
      size: 20000000,
      sha256Hex: ''.padLeft(64, 'a'),
    );
  }
}

void main() {
  testWidgets('Update Center shows current version and stable status',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final fake = _FakeUpdateCenter();
    await tester.pumpWidget(MaterialApp(
      home: UpdateCenterScreen(updater: fake),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('POTV Update Center'), findsOneWidget);
    expect(find.text('0.8.0 · código 13'), findsOneWidget);
    expect(find.textContaining('POTV está actualizado'), findsOneWidget);
    expect(fake.active, PotvUpdateChannel.stable);
  });

  testWidgets('user can choose beta and see new release notes',
      (tester) async {
    final fake = _FakeUpdateCenter();
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
      home: UpdateCenterScreen(updater: fake),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Beta').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(fake.active, PotvUpdateChannel.beta);
    expect(find.text('POTV 0.9.0-beta.1'), findsOneWidget);
    expect(find.text('Nuevo Sports Hub y TV en vivo'), findsOneWidget);
    expect(find.byKey(const ValueKey('ota-download')), findsOneWidget);
  });
}
