/// POTV customer sessions authenticate only against our own control plane.
///
/// Neither these tokens nor provider-side accounts are exposed to third-party
/// addon servers. The upstream content provider is contacted by the backend.
Future<Map<String, String>> potvCustomerSessionHeaders(
  Uri endpoint,
  Future<String?> Function() readSessionToken,
) async {
  if (endpoint.scheme != 'https' ||
      endpoint.host.toLowerCase() != 'potv.fxqubit.com' ||
      endpoint.userInfo.isNotEmpty ||
      endpoint.hasQuery ||
      endpoint.hasFragment ||
      !endpoint.path.startsWith('/api/v1')) {
    return const {};
  }
  try {
    final token = (await readSessionToken())?.trim();
    if (token == null || token.isEmpty ||
        token.contains('\n') || token.contains('\r')) {
      return const {};
    }
    return {'Authorization': 'Bearer $token'};
  } catch (_) {
    return const {};
  }
}
