import 'package:flutter_test/flutter_test.dart';
import 'package:potv/data/resolution/potv_customer_session_headers.dart';

void main() {
  test('POTV customer token is sent to the official gateway only', () async {
    final headers = await potvCustomerSessionHeaders(
      Uri.parse('https://potv.fxqubit.com/api/v1/'),
      () async => 'potv-customer-fixture',
    );
    expect(headers, {'Authorization': 'Bearer potv-customer-fixture'});
  });

  test('never send POTV customer token to a third-party provider', () async {
    var reads = 0;
    for (final url in [
      'https://third-party.example/api/v1/',
      'https://potv.fxqubit.com.evil.example/api/v1/',
      'http://potv.fxqubit.com/api/v1/',
      'https://customer:token@potv.fxqubit.com/api/v1/',
      'https://potv.fxqubit.com/private/',
    ]) {
      final headers = await potvCustomerSessionHeaders(Uri.parse(url), () async {
        reads++;
        return 'private-test-token';
      });
      expect(headers, isEmpty, reason: url);
    }
    expect(reads, 0);
  });

  test('missing session or read failure cannot leak credentials', () async {
    final url = Uri.parse('https://potv.fxqubit.com/api/v1/');
    expect(await potvCustomerSessionHeaders(url, () async => null), isEmpty);
    expect(await potvCustomerSessionHeaders(url, () async => '  '), isEmpty);
    expect(
      await potvCustomerSessionHeaders(url, () async => throw StateError('locked')),
      isEmpty,
    );
  });
}
