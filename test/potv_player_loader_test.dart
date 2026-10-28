import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potv/features/player/potv_player_loader.dart';

void main() {
  testWidgets('player loading displays the bundled animated POTV flag',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: PotvPlayerLoader(size: 92))),
    ));
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<AssetImage>());
    expect((image.image as AssetImage).assetName,
        'assets/branding/POTV_loader_animado_transparente.webp');
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
