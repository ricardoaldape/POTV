import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potv/ui/branding/potv_animated_assets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Permanent POTV animated assets are packaged in the app', () async {
    final splash = await rootBundle.load(PotvAnimatedAssets.startup);
    final loader = await rootBundle.load(PotvAnimatedAssets.loading);
    expect(splash.lengthInBytes, greaterThan(100000));
    expect(loader.lengthInBytes, greaterThan(100000));
  });

  testWidgets('Intro shows the animated WebP and then yields to the app', (tester) async {
    await tester.pumpWidget(const PotvStartupSplash(child: ColoredBox(color: Colors.black)));
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as AssetImage).assetName, PotvAnimatedAssets.startup);
    await tester.pump(const Duration(milliseconds: 2800));
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('Loading uses the POTV animated flag, not a circle', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: PotvLoadingFlag())));
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as AssetImage).assetName, PotvAnimatedAssets.loading);
  });
}
