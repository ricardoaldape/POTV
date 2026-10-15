import 'account_auth_service.dart';

/// Authorization header for the first-party POTV gateway only.
///
/// The VOD resolver can have an externally configured URL. Passing a POTV
/// account token to that URL would disclose a customer's session to a
/// different provider. The allowlist is deliberately an exact host match.
class PotvContentAuthHeaders {
  const PotvContentAuthHeaders._();

  static bool isFirstPartyGateway(Uri? endpoint) =>
      endpoint != null &&
      endpoint.scheme == 'https' &&
      endpoint.host.toLowerCase() == 'potv.fxqubit.com' &&
      (endpoint.port == 443) &&
      endpoint.userInfo.isEmpty;

  static Future<Map<String, String>> forEndpoint(
    Uri? endpoint, {
    Future<String?> Function()? tokenReader,
  }) async {
    if (!isFirstPartyGateway(endpoint)) return const {};

    String? token;
    try {
      token = await (tokenReader ?? AccountAuthService().sessionToken).call();
    } catch (_) {
      return const {};
    }
    final value = token?.trim() ?? '';
    if (value.isEmpty || value.contains(RegExp(r'[\r\n]'))) {
      return const {};
    }
    return {'Authorization': 'Bearer $value'};
  }
}
