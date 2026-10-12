import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potv/features/content/preload_network_policy.dart';

void main() {
  test('allows speculative loading only on Wi-Fi and Ethernet', () {
    expect(PreloadNetworkPolicy.allows([ConnectivityResult.wifi]), isTrue);
    expect(PreloadNetworkPolicy.allows([ConnectivityResult.ethernet]), isTrue);
  });

  test('protects mobile data and unclear routes', () {
    expect(PreloadNetworkPolicy.allows([ConnectivityResult.mobile]), isFalse);
    expect(PreloadNetworkPolicy.allows([ConnectivityResult.none]), isFalse);
    expect(PreloadNetworkPolicy.allows([ConnectivityResult.vpn]), isFalse);
    expect(PreloadNetworkPolicy.allows([]), isFalse);
    expect(
      PreloadNetworkPolicy.allows([
        ConnectivityResult.wifi,
        ConnectivityResult.mobile,
      ]),
      isFalse,
    );
  });
}
