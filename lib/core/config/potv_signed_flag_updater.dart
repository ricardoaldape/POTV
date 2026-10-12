import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;

import 'potv_runtime_flags.dart';

/// Downloads only authenticated, signed feature flags. Never accepts remote
/// executable code, credentials, provider endpoints or unsigned manifests.
///
/// Wire format (JSON):
/// {"payload":"<base64 UTF-8 JSON flags>","signature":"<base64 Ed25519>"}
/// The detached signature authenticates the exact decoded payload bytes.
class PotvSignedFlagUpdater {
  PotvSignedFlagUpdater({
    required this.store,
    required this.endpoint,
    required this.publicKey,
    required this.client,
  });

  final PotvRuntimeFlagStore store;
  final Uri endpoint;
  final SimplePublicKey publicKey;
  final http.Client client;

  static const maxEnvelopeBytes = 64 * 1024;

  /// Returns false, preserving the last known good flags, for any failure.
  Future<bool> refresh() async {
    if (endpoint.scheme != 'https' ||
        endpoint.host.isEmpty ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.hasFragment ||
        publicKey.type != KeyPairType.ed25519 ||
        publicKey.bytes.length != 32) {
      return false;
    }

    try {
      final response = await client
          .get(endpoint, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200 ||
          response.bodyBytes.length > maxEnvelopeBytes) {
        return false;
      }

      final envelope = jsonDecode(utf8.decode(response.bodyBytes));
      if (envelope is! Map<String, dynamic> ||
          envelope.keys.length != 2 ||
          envelope['payload'] is! String ||
          envelope['signature'] is! String) {
        return false;
      }

      final payload = base64.decode(envelope['payload'] as String);
      final signatureBytes = base64.decode(envelope['signature'] as String);
      if (payload.length > maxEnvelopeBytes ||
          signatureBytes.length != 64) {
        return false;
      }

      final signature = Signature(signatureBytes, publicKey: publicKey);
      final verified = await Ed25519().verify(payload, signature: signature);
      if (!verified) return false;
      return store.applyVerifiedManifest(utf8.decode(payload));
    } catch (_) {
      return false;
    }
  }
}

/// Compile-time production configuration. Missing values keep updates off.
/// Never bundle the Ed25519 *private* signing key in an app.
PotvSignedFlagUpdater? createConfiguredFlagUpdater({
  required PotvRuntimeFlagStore store,
  required http.Client client,
}) {
  const url = String.fromEnvironment('POTV_SIGNED_FLAGS_URL');
  const publicKeyBase64 = String.fromEnvironment('POTV_FLAGS_ED25519_PUBLIC_KEY');
  if (url.isEmpty || publicKeyBase64.isEmpty) return null;

  final endpoint = Uri.tryParse(url);
  if (endpoint == null || endpoint.scheme != 'https') return null;
  try {
    final keyBytes = base64.decode(publicKeyBase64);
    if (keyBytes.length != 32) return null;
    return PotvSignedFlagUpdater(
      store: store,
      endpoint: endpoint,
      publicKey: SimplePublicKey(keyBytes, type: KeyPairType.ed25519),
      client: client,
    );
  } catch (_) {
    return null;
  }
}
