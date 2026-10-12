import 'package:connectivity_plus/connectivity_plus.dart';

/// Best-effort guard against speculative traffic on metered/mobile networks.
/// Unknown VPN or mobile transports intentionally disable proactive requests.
class PreloadNetworkPolicy {
  const PreloadNetworkPolicy._();

  static bool allows(List<ConnectivityResult> transports) {
    if (transports.isEmpty ||
        transports.contains(ConnectivityResult.none) ||
        transports.contains(ConnectivityResult.mobile) ||
        transports.contains(ConnectivityResult.vpn)) {
      return false;
    }
    return transports.contains(ConnectivityResult.wifi) ||
        transports.contains(ConnectivityResult.ethernet);
  }

  static Future<bool> isLikelyUnmetered() async {
    try {
      final transports = await Connectivity().checkConnectivity();
      return allows(transports);
    } catch (_) {
      // A missing plugin or unknown network must never start prefetch traffic.
      return false;
    }
  }
}
