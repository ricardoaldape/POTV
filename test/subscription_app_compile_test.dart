import 'package:flutter_test/flutter_test.dart';
import 'package:potv/app/potv_app.dart';

void main() {
  test('subscription gate compiles with the POTV app root', () {
    expect(const PotvApp(), isA<PotvApp>());
  });
}
