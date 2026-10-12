import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:potv/core/config/potv_runtime_flags.dart';
import 'package:potv/core/config/potv_signed_flag_updater.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<({PotvSignedFlagUpdater updater, PotvRuntimeFlagStore store})> setup({
    required String payload,
    bool tamperSignature = false,
    int status = 200,
    Uri? endpoint,
  }) async {
    final keyPair = await Ed25519().newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final payloadBytes = utf8.encode(payload);
    final signature = await Ed25519().sign(payloadBytes, keyPair: keyPair);
    final signatureBytes = [...signature.bytes];
    if (tamperSignature) signatureBytes[0] ^= 0x01;

    final envelope = jsonEncode({
      'payload': base64.encode(payloadBytes),
      'signature': base64.encode(signatureBytes),
    });

    final store = PotvRuntimeFlagStore(await SharedPreferences.getInstance());
    return (
      updater: PotvSignedFlagUpdater(
        store: store,
        endpoint: endpoint ?? Uri.parse('https://config.example.org/flags'),
        publicKey: publicKey,
        client: MockClient((request) async =>
            http.Response(envelope, status,
                headers: {'content-type': 'application/json'})),
      ),
      store: store,
    );
  }

  test('accepts authenticated flag changes and saves last known good', () async {
    final fixture = await setup(
      payload: '{"version":1,"flags":{"sports_calendar":false}}',
    );
    expect(await fixture.updater.refresh(), isTrue);
    expect(fixture.store.current.version, 1);
    expect(fixture.store.current.enabled('sports_calendar'), isFalse);
    final restored =
        PotvRuntimeFlagStore(await SharedPreferences.getInstance())..load();
    expect(restored.current.version, 1);
    expect(restored.current.enabled('sports_calendar'), isFalse);
  });

  test('rejects invalid Ed25519 signature without changing local state',
      () async {
    final fixture = await setup(
      payload: '{"version":1,"flags":{"sports_calendar":false}}',
      tamperSignature: true,
    );
    expect(await fixture.updater.refresh(), isFalse);
    expect(fixture.store.current.version, 0);
    expect(fixture.store.current.enabled('sports_calendar'), isTrue);
  });

  test('rejects insecure endpoint or failed HTTP response', () async {
    final fixture = await setup(
      payload: '{"version":1,"flags":{"sports_calendar":false}}',
      endpoint: Uri.parse('http://config.example.org/flags'),
    );
    expect(await fixture.updater.refresh(), isFalse);
    final failed = await setup(
      payload: '{"version":1,"flags":{"sports_calendar":false}}',
      status: 503,
    );
    expect(await failed.updater.refresh(), isFalse);
  });

  test('rejects stale signed payloads after a valid update', () async {
    final fixture = await setup(
      payload: '{"version":1,"flags":{"sports_calendar":false}}',
    );
    expect(await fixture.updater.refresh(), isTrue);
    expect(await fixture.updater.refresh(), isFalse);
    expect(fixture.store.current.version, 1);
  });
}
