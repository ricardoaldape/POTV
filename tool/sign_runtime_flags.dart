import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

/// Produces a POTV signed feature-flags envelope for static HTTPS hosting.
///
/// Usage:
/// POTV_FLAGS_ED25519_PRIVATE_SEED=BASE64_PRIVATE_SEED
/// dart run tool/sign_runtime_flags.dart input_flags.json signed_flags.json
///
/// Never commit or echo the private seed. Only use this from an operator
/// workstation or a protected CI job. Input is checked before signing.
Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln(
      'Usage: dart run tool/sign_runtime_flags.dart input.json output.json',
    );
    exitCode = 2;
    return;
  }
  final seedValue = Platform.environment['POTV_FLAGS_ED25519_PRIVATE_SEED'];
  if (seedValue == null || seedValue.isEmpty) {
    stderr.writeln('Missing private signing seed in environment.');
    exitCode = 2;
    return;
  }

  List<int> seed;
  try {
    seed = base64.decode(seedValue);
  } on FormatException {
    stderr.writeln('Private signing seed must be base64 encoded.');
    exitCode = 2;
    return;
  }
  if (seed.length != 32) {
    stderr.writeln('Private signing seed must contain exactly 32 bytes.');
    exitCode = 2;
    return;
  }

  final input = File(args[0]);
  final output = File(args[1]);
  if (!await input.exists()) {
    stderr.writeln('Input manifest was not found.');
    exitCode = 2;
    return;
  }
  final bytes = await input.readAsBytes();
  if (bytes.length > 32 * 1024) {
    stderr.writeln('Manifest exceeds 32 KiB.');
    exitCode = 2;
    return;
  }

  const allowed = <String>{
    'sports_calendar',
    'sports_event_matching',
    'live_tv_catalog',
    'live_tv_epg',
    'predictive_preload',
    'youtube_integration',
    'external_source_resolution',
  };
  try {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic> ||
        decoded.keys.length != 2 ||
        !decoded.containsKey('version') ||
        !decoded.containsKey('flags') ||
        decoded['version'] is! int ||
        (decoded['version'] as int) < 1 ||
        decoded['flags'] is! Map<String, dynamic>) {
      throw const FormatException('Invalid manifest structure');
    }
    final flags = decoded['flags'] as Map<String, dynamic>;
    if (flags.keys.any((key) => !allowed.contains(key)) ||
        flags.values.any((value) => value is! bool)) {
      throw const FormatException('Invalid feature flag');
    }
  } catch (_) {
    stderr.writeln('Invalid flags JSON: expected version and boolean flags.');
    exitCode = 2;
    return;
  }

  final keyPair = await Ed25519().newKeyPairFromSeed(seed);
  final publicKey = await keyPair.extractPublicKey();
  final signature = await Ed25519().sign(bytes, keyPair: keyPair);
  final envelope = jsonEncode({
    'payload': base64.encode(bytes),
    'signature': base64.encode(signature.bytes),
  });
  await output.writeAsString('$envelope\n', flush: true);
  stdout.writeln('Signed manifest written to ${output.path}');
  stdout.writeln('Public verification key (safe to embed): ${base64.encode(publicKey.bytes)}');
}
